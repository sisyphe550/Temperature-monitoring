import Foundation
import Testing
@testable import SensorRuntime
@testable import TemperatureCore

// Audit-only: correct expectations against the production controller, using
// deterministic hardware facts and a recoverable transport fault.
@Suite(.serialized) struct ProductAuditSensorRegressionTests {
    @Test func missingOneRequiredCPUMemberStopsStartup() async throws {
        let profile = try Configuration.bundledProfile()
        let raw = auditCPUCatalog(profile: profile, omitFirst: true)
        let qualified = try ProfileRegistry(profile: profile).qualify(raw)
        #expect(qualified.available.count == 11)
        let clock = TestClock(now: Fixtures.timestamp(ms: 0))
        let client = ScriptableSensorClient(clock: clock, catalog: qualified)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProductAuditIncompleteCPU-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = SessionPersistenceActor(databaseURL: directory.appendingPathComponent("monitor.sqlite"))
        let metadata = SessionMetadata(sessionID: SessionID(UUID()), startedWallUnixNS: 1,
            model: "Mac16,13", osBuild: "24G419", appVersion: "audit")
        let controller = SessionMonitorController(clock: clock, client: client, session: session,
            sessionMetadata: metadata, configuration: try Configuration.bundledDefaults())
        var startupWasRejected = false
        do { try await controller.start() } catch { startupWasRejected = true }
        #expect(startupWasRejected)
        await controller.stop()
        try await session.closeAndDeleteSession()
    }

    @Test func oneRecoverableTimeoutDoesNotPermanentlyStopProductionSampling() async throws {
        let profile = try Configuration.bundledProfile()
        let clock = TestClock(now: Fixtures.timestamp(ms: 0))
        let transport = AuditRecoverableTransport(clock: clock, catalog: auditCPUCatalog(profile: profile))
        let client = QualifiedSensorClient(transport: transport, registry: ProfileRegistry(profile: profile))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProductAuditTimeout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = SessionPersistenceActor(databaseURL: directory.appendingPathComponent("monitor.sqlite"))
        let metadata = SessionMetadata(sessionID: SessionID(UUID()), startedWallUnixNS: 1,
            model: "Mac16,13", osBuild: "24G419", appVersion: "audit")
        let controller = SessionMonitorController(clock: clock, client: client, session: session,
            sessionMetadata: metadata, configuration: try Configuration.bundledDefaults())
        try await controller.start()
        for ms in stride(from: Int64(200), through: Int64(2_000), by: 200) {
            clock.advance(to: Fixtures.timestamp(ms: ms))
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let actualTransportReads = await transport.readCount
        let rawCount = try await session.rows(in: "raw_samples")
        #expect(actualTransportReads > 1)
        #expect(rawCount > 0)
        await controller.stop()
        try await session.closeAndDeleteSession()
    }
}

private func auditCPUCatalog(profile: SensorProfile, omitFirst: Bool = false) -> DiscoveredCatalog {
    let keys = omitFirst ? Array(profile.cpuKeys.dropFirst()) : profile.cpuKeys
    return DiscoveredCatalog(generation: 1, sources: keys.map { key in
        DiscoveredSource(transportHandle: "smc:\(key)", provider: .smc, rawKey: key,
            registryID: "audit-\(key)", encoding: profile.expectedSMCEncoding,
            byteCount: profile.expectedSMCSizeBytes)
    })
}

private actor AuditRecoverableTransport: SensorTransport {
    let clock: TestClock
    let catalog: DiscoveredCatalog
    private(set) var readCount = 0
    private(set) var discoverCount = 0
    init(clock: TestClock, catalog: DiscoveredCatalog) { self.clock = clock; self.catalog = catalog }
    func discoverRaw() async throws -> DiscoveredCatalog { discoverCount += 1; return catalog }
    func readRaw(_ request: TransportReadRequest) async throws -> TransportReadBatch {
        readCount += 1
        if readCount == 1 {
            throw MonitorFailure(code: .sensorTimeout, severity: .degraded,
                component: "AuditTransport", operation: "read", retryCount: 0,
                sourceID: nil, underlyingCode: "one_recoverable_timeout")
        }
        let now = clock.now()
        return TransportReadBatch(requestID: request.requestID, generation: request.generation,
            readings: request.transportHandles.map { handle in
                TransportReading(transportHandle: handle, started: now, finished: now,
                    outcome: .success(valueC: 70, sourceWallUnixNS: nil, freshness: .unknown))
            })
    }
    func close() async {}
}
