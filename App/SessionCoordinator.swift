import Foundation
import SensorRuntime
import TemperatureCore

public enum SessionCoordinatorError: Error, Sendable, Equatable {
    case alreadyRunning
    case notRunning
    case instanceAlreadyHeld
    case startupFailed(String)
}

public actor SessionCoordinator {
    private let clock: MonitorClock
    private let client: any SensorClient
    private let configuration: RuntimeConfiguration
    private let paths: SessionPaths
    private var sessionLock: SessionLock?
    private var controller: SessionMonitorController?
    private var sessionID: SessionID?
    private var fatalReceipt: FatalDisplayReceipt?
    private var metadata: SessionMetadata?
    private var lifecycleBusy = false
    private var lifecycleWaiters: [CheckedContinuation<Void, Never>] = []

    public init(
        clock: MonitorClock,
        client: any SensorClient,
        configuration: RuntimeConfiguration,
        applicationSupportBase: URL
    ) {
        self.clock = clock
        self.client = client
        self.configuration = configuration
        paths = SessionPaths(bundleID: configuration.bundleID, baseDirectory: applicationSupportBase)
    }

    public func start(sessionMetadata: SessionMetadata) async throws {
        await beginLifecycleOperation()
        defer { endLifecycleOperation() }
        guard controller == nil else {
            throw SessionCoordinatorError.alreadyRunning
        }
        metadata = sessionMetadata
        let lock = try SessionLock.acquire(at: paths.lockURL)
        sessionLock = lock
        let cleanup = SessionCleanup(
            bundleID: configuration.bundleID,
            schemaVersion: SessionCleanup.expectedSchemaVersion
        )
        _ = try cleanup.cleanupOrphanedSessions(paths: paths, excludingSessionID: nil)
        sessionID = sessionMetadata.sessionID
        metadata = sessionMetadata
        let sessionDirectory = paths.sessionDirectory(sessionID: sessionMetadata.sessionID)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        try cleanup.writeMarker(for: sessionMetadata.sessionID, in: sessionDirectory)
        let persistence = SessionPersistenceActor(
            databaseURL: paths.databaseURL(sessionID: sessionMetadata.sessionID)
        )
        let controller = SessionMonitorController(
            clock: clock,
            client: client,
            session: persistence,
            sessionMetadata: sessionMetadata,
            configuration: configuration,
            diagnosticsDirectory: paths.appSupportRoot.appendingPathComponent("Diagnostics", isDirectory: true)
        )
        self.controller = controller
        try await controller.start()
    }

    public func suspendForSleep() async throws {
        await beginLifecycleOperation()
        defer { endLifecycleOperation() }
        guard let controller else {
            throw SessionCoordinatorError.notRunning
        }
        if await controller.isSuspended { return }
        try await controller.suspendForSleep()
    }

    public func resumeAfterWake() async throws {
        await beginLifecycleOperation()
        defer { endLifecycleOperation() }
        guard let controller else {
            throw SessionCoordinatorError.notRunning
        }
        guard await controller.isSuspended else { return }
        try await controller.resumeAfterWake()
    }

    public func stop() async {
        await beginLifecycleOperation()
        defer { endLifecycleOperation() }
        await controller?.stop()
        let shutdown = await controller?.lastShutdownOutcome()
        if let shutdown, !shutdown.incompleteSteps.isEmpty {
            recordShutdownDeadlineExceeded(incompleteSteps: shutdown.incompleteSteps)
        }
        if let sessionID, shutdown?.incompleteSteps.isEmpty != false {
            let cleanup = SessionCleanup(bundleID: configuration.bundleID)
            do { try cleanup.deleteSessionDirectory(at: paths.sessionDirectory(sessionID: sessionID), sessionID: sessionID, paths: paths) }
            catch { fputs("TemperatureMonitor session cleanup incomplete: \(error)\n", stderr) }
        }
        controller = nil
        sessionID = nil
        sessionLock?.release()
        sessionLock = nil
    }

    private func beginLifecycleOperation() async {
        if lifecycleBusy { await withCheckedContinuation { lifecycleWaiters.append($0) } }
        else { lifecycleBusy = true }
    }

    private func endLifecycleOperation() {
        if lifecycleWaiters.isEmpty { lifecycleBusy = false }
        else { lifecycleWaiters.removeFirst().resume() }
    }

    public var shutdownBudgetMS: Int { configuration.shutdownBudgetMS }

    public func recordShutdownDeadlineExceeded(incompleteSteps: [String] = ["await_runtime_stop", "delete_session_directory"]) {
        guard let metadata else { return }
        let directory = paths.appSupportRoot.appendingPathComponent("Diagnostics", isDirectory: true)
        let logger = DiagnosticLogger(directory: directory, configuration: configuration)
        let failure = fatalReceipt?.failure ?? MonitorFailure(code: .databaseClean, severity: .fatal,
            component: "SessionCoordinator", operation: "shutdown", retryCount: 0, sourceID: nil,
            underlyingCode: "shutdown_deadline_exceeded")
        let context = DiagnosticContext(sessionID: metadata.sessionID, appVersion: metadata.appVersion, model: metadata.model, osBuild: metadata.osBuild)
        try? logger.append(DiagnosticLogEntry(failure: failure, context: context))
        let report = FatalReport(frozenFailure: failure, sessionID: metadata.sessionID,
            appVersion: metadata.appVersion, model: metadata.model, osBuild: metadata.osBuild,
            incompleteShutdownSteps: incompleteSteps, writtenAt: Date())
        _ = try? ReportWriter(directory: directory, configuration: configuration).write(report)
    }

    public func recordFatal(
        _ failure: MonitorFailure,
        reportPath: String?
    ) async -> FatalDisplayReceipt {
        if let fatalReceipt { return fatalReceipt }
        let directory = paths.appSupportRoot.appendingPathComponent("Diagnostics", isDirectory: true)
        let logger = DiagnosticLogger(directory: directory, configuration: configuration)
        let runtimeReportPath = await controller?.fatalReportPath()
        var resolvedReportPath = reportPath ?? runtimeReportPath
        if let metadata, resolvedReportPath == nil {
            let context = DiagnosticContext(sessionID: metadata.sessionID, appVersion: metadata.appVersion,
                model: metadata.model, osBuild: metadata.osBuild)
            do { try logger.append(DiagnosticLogEntry(failure: failure, context: context)) }
            catch { fputs("TemperatureMonitor diagnostic write failed: \(error)\n", stderr) }
            let report = FatalReport(frozenFailure: failure, sessionID: metadata.sessionID,
                appVersion: metadata.appVersion, model: metadata.model, osBuild: metadata.osBuild,
                incompleteShutdownSteps: [], writtenAt: Date())
            resolvedReportPath = (try? ReportWriter(directory: directory, configuration: configuration).write(report))?.url?.path
        }
        let receipt = FatalDisplayReceipt(
            failure: failure,
            visibleAt: clock.now(),
            configuration: configuration,
            reportPath: resolvedReportPath
        )
        fatalReceipt = receipt
        return receipt
    }

    public func freezeForFatal() async { await controller?.freezeForFatal() }

    public func lastRuntimeFailure() async -> MonitorFailure? { await controller?.lastAcceptFailure() }

    public func currentFatalReceipt() -> FatalDisplayReceipt? {
        fatalReceipt
    }

    public func snapshots() async -> AsyncStream<Snapshot>? {
        await controller?.snapshots()
    }

    public func queryHistory(_ request: HistoryRequest) async throws -> HistoryResult {
        guard let controller else {
            throw SessionCoordinatorError.notRunning
        }
        return try await controller.history(request)
    }

    public func setCPUPeriod(milliseconds: Int) async throws {
        guard let controller else {
            throw SessionCoordinatorError.notRunning
        }
        try await controller.setCPUPeriod(milliseconds: milliseconds)
    }
}
