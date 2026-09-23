import Foundation
import TemperatureCore

public actor SessionMonitorController: MonitorController {
    private static let snapshotIntervalNS: Int64 = 200_000_000

    private let clock: MonitorClock
    private let client: any SensorClient
    private let session: SessionPersistenceActor
    private let sessionMetadata: SessionMetadata
    private let configuration: RuntimeConfiguration
    private var engine: MonitorEngine?
    private var coordinator: ProcessingCoordinator?
    private var snapshotStream: AsyncStream<Snapshot>?
    private var snapshotContinuation: AsyncStream<Snapshot>.Continuation?
    private var snapshotTask: Task<Void, Never>?
    private var running = false
    private var stopped = false
    private var lastSnapshotPublishElapsedNS: Int64?

    public init(
        clock: MonitorClock,
        client: any SensorClient,
        session: SessionPersistenceActor,
        sessionMetadata: SessionMetadata,
        configuration: RuntimeConfiguration
    ) {
        self.clock = clock
        self.client = client
        self.session = session
        self.sessionMetadata = sessionMetadata
        self.configuration = configuration
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
            sessionStartedAt: startedAt
        )
        let coordinator = ProcessingCoordinator(
            clock: clock,
            client: client,
            reservation: await session.reservationCapability(),
            engine: engine,
            configuration: configuration
        )
        self.engine = engine
        self.coordinator = coordinator
        running = true
        stopped = false
        await coordinator.start(catalog: catalog)
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

    public func lastAcceptFailure() async -> MonitorFailure? {
        await coordinator?.lastAcceptFailure
    }

    public func stop() async {
        guard !stopped else {
            return
        }
        stopped = true
        running = false

        snapshotTask?.cancel()
        snapshotTask = nil
        snapshotContinuation?.finish()
        snapshotContinuation = nil
        snapshotStream = nil
        lastSnapshotPublishElapsedNS = nil
        await coordinator?.stop()
        coordinator = nil
        engine = nil
        await client.close()
        lastShutdownResult = ShutdownResult(stepResults: [
            ShutdownStepResult(name: "stop_snapshot_loop", completed: true),
            ShutdownStepResult(name: "stop_coordinator", completed: true),
            ShutdownStepResult(name: "close_client", completed: true),
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
        snapshotTask?.cancel()
        snapshotTask = nil
        try await coordinator.suspendForSleep()
        await client.close()
    }

    public func resumeAfterWake() async throws {
        guard !stopped, let coordinator, let engine else {
            throw Self.failure(
                code: .processingValidate,
                operation: "resumeAfterWake",
                underlyingCode: "not_suspended"
            )
        }
        let catalog = try await client.discover()
        let definitions = try SeriesCatalogBuilder.definitions(from: catalog)
        await engine.replaceDefinitions(definitions)
        try await session.prune(nowElapsedNS: clock.now().elapsedNS)
        try await coordinator.resumeAfterWake(catalog: catalog)
        running = true
        if snapshotContinuation != nil {
            startSnapshotLoop()
        }
    }

    public func lastShutdownOutcome() -> ShutdownResult? {
        lastShutdownResult
    }

    private var lastShutdownResult: ShutdownResult?

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
