import Foundation
import TemperatureCore

public actor SessionMonitorController: MonitorController {
    private static let snapshotIntervalNS: Int64 = 200_000_000

    private let clock: MonitorClock
    private let client: any SensorClient
    private let session: SessionPersistenceActor
    private let sessionMetadata: SessionMetadata
    private let configuration: RuntimeConfiguration
    private let diagnosticLogger: DiagnosticLogger?
    private let reportWriter: ReportWriter?
    private var runtimeFatalReportPath: String?
    private var engine: MonitorEngine?
    private var coordinator: ProcessingCoordinator?
    private var snapshotStream: AsyncStream<Snapshot>?
    private var snapshotContinuation: AsyncStream<Snapshot>.Continuation?
    private var snapshotTask: Task<Void, Never>?
    private var maintenanceTask: Task<Void, Never>?
    private var running = false
    private var stopped = false
    private var stopTask: Task<Void, Never>?
    private var lastSnapshotPublishElapsedNS: Int64?

    public init(
        clock: MonitorClock,
        client: any SensorClient,
        session: SessionPersistenceActor,
        sessionMetadata: SessionMetadata,
        configuration: RuntimeConfiguration,
        diagnosticsDirectory: URL? = nil
    ) {
        self.clock = clock
        self.client = client
        self.session = session
        self.sessionMetadata = sessionMetadata
        self.configuration = configuration
        diagnosticLogger = diagnosticsDirectory.map { DiagnosticLogger(directory: $0, configuration: configuration) }
        reportWriter = diagnosticsDirectory.map { ReportWriter(directory: $0, configuration: configuration) }
    }

    public func start() async throws {
        guard !running else {
            return
        }
        try await session.open(sessionMetadata)
        let catalog = try await client.discover()
        let definitions = try SeriesCatalogBuilder.definitions(from: catalog)
        let startedAt = clock.now()
        let engine = MonitorEngine(
            clock: clock,
            commit: await session.commitCapability(),
            session: sessionMetadata,
            configuration: configuration,
            definitions: definitions,
            cpuPeriodMS: configuration.cpuDefaultMS,
            qualifiedSources: catalog.available,
            sessionStartedAt: startedAt,
            capabilityValues: try SeriesCatalogBuilder.unavailableValues(from: catalog)
        )
        let coordinator = ProcessingCoordinator(
            clock: clock,
            client: client,
            reservation: await session.reservationCapability(),
            engine: engine,
            configuration: configuration,
            diagnosticSink: { [weak self] failure in await self?.recordRuntimeFailure(failure) }
        )
        self.engine = engine
        self.coordinator = coordinator
        running = true
        stopped = false
        await coordinator.start(catalog: catalog)
        startMaintenanceLoop()
        if snapshotContinuation != nil {
            startSnapshotLoop()
        }
    }

    public func setCPUPeriod(milliseconds: Int) async throws {
        guard running, let coordinator, let engine else {
            throw Self.failure(
                code: .processingValidate,
                operation: "setCPUPeriod",
                underlyingCode: "not_running"
            )
        }
        await coordinator.setCPUPeriod(milliseconds: milliseconds)
        await engine.setCPUPeriod(milliseconds: milliseconds)
    }

    public func snapshots() async -> AsyncStream<Snapshot> {
        if let snapshotStream {
            return snapshotStream
        }
        let (stream, continuation) = AsyncStream.makeStream(
            of: Snapshot.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        snapshotContinuation = continuation
        snapshotStream = stream
        if running {
            startSnapshotLoop()
        }
        return stream
    }

    public func history(_ request: HistoryRequest) async throws -> HistoryResult {
        guard running, let engine else {
            throw Self.failure(
                code: .processingValidate,
                operation: "history",
                underlyingCode: "not_running"
            )
        }
        if request.range == .fiveMinutes {
            return await engine.realtime(request)
        }
        return try await session.query(request)
    }

    public var isStopped: Bool {
        stopped
    }

    public func samplingStatistics() async -> SamplingStatistics {
        await coordinator?.samplingStatistics() ?? SamplingStatistics()
    }

    public func persistenceQueueSnapshot() async -> PersistenceQueueSnapshot {
        await session.persistenceQueueSnapshot()
    }

    public func waitForPersistenceDrain(maxSeconds: Int) async {
        for _ in 0..<maxSeconds {
            let snapshot = await session.persistenceQueueSnapshot()
            if snapshot.acceptsNewReservations {
                return
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    public func lastAcceptFailure() async -> MonitorFailure? {
        await coordinator?.lastAcceptFailure
    }

    public func freezeForFatal() async {
        running = false
        let maintenance = maintenanceTask
        let snapshot = snapshotTask
        maintenance?.cancel()
        snapshot?.cancel()
        maintenanceTask = nil
        snapshotTask = nil
        await coordinator?.stop()
        await maintenance?.value
        await snapshot?.value
        snapshotContinuation?.finish()
    }

    public var isSuspended: Bool { !running && !stopped && coordinator != nil }

    public func fatalReportPath() -> String? { runtimeFatalReportPath }

    private func recordRuntimeFailure(_ failure: MonitorFailure) {
        let context = DiagnosticContext(sessionID: sessionMetadata.sessionID, appVersion: sessionMetadata.appVersion,
            model: sessionMetadata.model, osBuild: sessionMetadata.osBuild)
        do { try diagnosticLogger?.append(DiagnosticLogEntry(failure: failure, context: context)) }
        catch { fputs("TemperatureMonitor diagnostic write failed: \(error)\n", stderr) }
        if failure.severity == .fatal, runtimeFatalReportPath == nil {
            let report = FatalReport(frozenFailure: failure, sessionID: sessionMetadata.sessionID,
                appVersion: sessionMetadata.appVersion, model: sessionMetadata.model, osBuild: sessionMetadata.osBuild,
                incompleteShutdownSteps: [], writtenAt: Date())
            runtimeFatalReportPath = (try? reportWriter?.write(report))?.url?.path
        }
    }

    public func stop() async {
        if let stopTask { await stopTask.value; return }
        let task = Task { await self.performStop() }
        stopTask = task
        await task.value
    }

    private func performStop() async {
        stopped = true
        running = false
        let maintenance = maintenanceTask
        let snapshot = snapshotTask
        maintenance?.cancel()
        snapshot?.cancel()
        maintenanceTask = nil
        snapshotTask = nil
        await coordinator?.stop()
        await maintenance?.value
        await snapshot?.value
        snapshotContinuation?.finish()
        snapshotContinuation = nil
        snapshotStream = nil
        lastSnapshotPublishElapsedNS = nil
        coordinator = nil
        engine = nil
        await client.close()
        var deleted = true
        do { try await session.closeAndDeleteSession() }
        catch {
            deleted = false
            recordRuntimeFailure((error as? MonitorFailure) ?? Self.failure(code: .databaseClean,
                operation: "closeAndDeleteSession", underlyingCode: String(describing: error)))
        }
        lastShutdownResult = ShutdownResult(stepResults: [
            ShutdownStepResult(name: "stop_snapshot_loop", completed: true),
            ShutdownStepResult(name: "stop_maintenance_loop", completed: true),
            ShutdownStepResult(name: "stop_coordinator", completed: true),
            ShutdownStepResult(name: "close_client", completed: true),
            ShutdownStepResult(name: "close_and_delete_session", completed: deleted),
        ])
    }

    public func suspendForSleep() async throws {
        guard running, !stopped, let coordinator else {
            throw Self.failure(
                code: .processingValidate,
                operation: "suspendForSleep",
                underlyingCode: "not_running"
            )
        }
        running = false
        let maintenance = maintenanceTask
        let snapshot = snapshotTask
        maintenance?.cancel()
        snapshot?.cancel()
        maintenanceTask = nil
        snapshotTask = nil
        try await coordinator.suspendForSleep()
        await maintenance?.value
        await snapshot?.value
        await client.releaseConnection()
    }

    public func resumeAfterWake() async throws {
        guard !stopped, let coordinator, engine != nil else {
            throw Self.failure(
                code: .processingValidate,
                operation: "resumeAfterWake",
                underlyingCode: "not_suspended"
            )
        }
        let catalog = try await client.discover()
        let definitions = try SeriesCatalogBuilder.definitions(from: catalog)
        _ = definitions
        try await coordinator.prepareForWakeMaintenance()
        try await session.prune(nowElapsedNS: clock.now().elapsedNS)
        try await coordinator.resumeAfterWake(catalog: catalog)
        running = true
        startMaintenanceLoop()
        if snapshotContinuation != nil {
            startSnapshotLoop()
        }
    }

    public func lastShutdownOutcome() -> ShutdownResult? {
        lastShutdownResult
    }

    private var lastShutdownResult: ShutdownResult?

    private func startMaintenanceLoop() {
        maintenanceTask?.cancel()
        let firstDeadline = clock.now().elapsedNS + configuration.retentionTickSeconds * 1_000_000_000
        maintenanceTask = Task { [weak self, clock, configuration] in
            var next = firstDeadline
            while !Task.isCancelled {
                do { try await clock.sleep(untilElapsedNS: next) } catch { return }
                guard !Task.isCancelled, let self else { return }
                await self.performMaintenance()
                next = clock.now().elapsedNS + configuration.retentionTickSeconds * 1_000_000_000
            }
        }
    }

    private func performMaintenance() async {
        guard running, !stopped else { return }
        do { try await session.prune(nowElapsedNS: clock.now().elapsedNS) }
        catch {
            let failure = (error as? MonitorFailure) ?? Self.failure(code: .databaseClean,
                operation: "periodicPrune", underlyingCode: String(describing: error))
            await coordinator?.reportFailure(failure)
        }
        diagnosticLogger?.pruneExpired(now: Date())
    }

    private func startSnapshotLoop() {
        snapshotTask?.cancel()
        snapshotTask = Task {
            while !Task.isCancelled {
                let shouldContinue = await self.runSnapshotCycle()
                if !shouldContinue {
                    return
                }
            }
        }
    }

    private func runSnapshotCycle() async -> Bool {
        await publishSnapshotIfDue()
        let nextPublish = await nextSnapshotPublishElapsedNS()
        do {
            try await clock.sleep(untilElapsedNS: nextPublish)
            return true
        } catch {
            return false
        }
    }

    private func publishSnapshotIfDue() async {
        guard running, let engine, let snapshotContinuation else {
            return
        }
        let now = clock.now()
        if let lastSnapshotPublishElapsedNS,
           now.elapsedNS - lastSnapshotPublishElapsedNS < Self.snapshotIntervalNS {
            return
        }
        let snapshot = await engine.snapshot(at: now)
        snapshotContinuation.yield(snapshot)
        lastSnapshotPublishElapsedNS = now.elapsedNS
    }

    private func nextSnapshotPublishElapsedNS() async -> Int64 {
        let now = clock.now().elapsedNS
        guard let lastSnapshotPublishElapsedNS else {
            return now + Self.snapshotIntervalNS
        }
        return lastSnapshotPublishElapsedNS + Self.snapshotIntervalNS
    }

    private static func failure(
        code: MonitorErrorCode,
        operation: String,
        underlyingCode: String
    ) -> MonitorFailure {
        MonitorFailure(
            code: code,
            severity: .fatal,
            component: "SessionMonitorController",
            operation: operation,
            retryCount: 0,
            sourceID: nil,
            underlyingCode: underlyingCode
        )
    }
}
