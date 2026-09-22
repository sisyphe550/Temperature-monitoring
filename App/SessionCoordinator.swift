// W08 will compile this file inside the App target. Until the Xcode project exists,
// lifecycle orchestration is implemented in SensorRuntime and covered by Core tests.
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
        guard controller == nil else {
            throw SessionCoordinatorError.alreadyRunning
        }
        let lock = try SessionLock.acquire(at: paths.lockURL)
        sessionLock = lock
        let cleanup = SessionCleanup(
            bundleID: configuration.bundleID,
            schemaVersion: SessionCleanup.expectedSchemaVersion
        )
        _ = try cleanup.cleanupOrphanedSessions(paths: paths, excludingSessionID: nil)
        sessionID = sessionMetadata.sessionID
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
            configuration: configuration
        )
        self.controller = controller
        try await controller.start()
    }

    public func suspendForSleep() async throws {
        guard let controller else {
            throw SessionCoordinatorError.notRunning
        }
        try await controller.suspendForSleep()
    }

    public func resumeAfterWake() async throws {
        guard let controller else {
            throw SessionCoordinatorError.notRunning
        }
        try await controller.resumeAfterWake()
    }

    public func stop() async {
        await controller?.stop()
        controller = nil
        sessionID = nil
        sessionLock?.release()
        sessionLock = nil
    }

    public func recordFatal(
        _ failure: MonitorFailure,
        reportPath: String?
    ) -> FatalDisplayReceipt {
        let receipt = FatalDisplayReceipt(
            failure: failure,
            visibleAt: clock.now(),
            configuration: configuration,
            reportPath: reportPath
        )
        fatalReceipt = receipt
        return receipt
    }

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
