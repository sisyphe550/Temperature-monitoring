import Foundation
import Testing
@testable import SensorRuntime
@testable import TemperatureCore

// Regression inputs are software fixtures, not hardware qualification.
@Suite(.serialized) struct SensorRecoveryRegressionTests {
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
        let runtimeFailure = await controller.lastAcceptFailure()
        #expect(rawCount > 0, "runtime failure: \(String(describing: runtimeFailure))")
        await controller.stop()
        try await session.closeAndDeleteSession()
    }
    @Test func repeatedCPUTimeoutStopsAtRetryBudgetAndReportsFatal() async throws {
        let profile = try Configuration.bundledProfile()
        let clock = TestClock(now: Fixtures.timestamp(ms: 0))
        let transport = AuditRecoverableTransport(clock: clock, catalog: auditCPUCatalog(profile: profile), alwaysFail: true)
        let client = QualifiedSensorClient(transport: transport, registry: ProfileRegistry(profile: profile))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RetryBudget-\(UUID())")
        let session = SessionPersistenceActor(databaseURL: root.appendingPathComponent("monitor.sqlite"))
        let controller = SessionMonitorController(clock: clock, client: client, session: session,
            sessionMetadata: SessionMetadata(sessionID: SessionID(UUID()), startedWallUnixNS: 1, model: "Mac16,13", osBuild: "24G419", appVersion: "regression"), configuration: try Configuration.bundledDefaults(), diagnosticsDirectory: root.appendingPathComponent("Diagnostics"))
        try await controller.start()
        for ms in stride(from: Int64(200), through: 2000, by: 20) {
            clock.advance(to: Fixtures.timestamp(ms: ms))
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let failure = try #require(await controller.lastAcceptFailure())
        #expect(failure.code == .sensorRead, "failure: \(failure)")
        #expect(failure.severity == .fatal)
        #expect(failure.retryCount == 3)
        #expect((await transport.readCount) == 4)
        let diagnostics = root.appendingPathComponent("Diagnostics")
        let logs = try FileManager.default.contentsOfDirectory(at: diagnostics, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
        let text = try logs.map { try String(contentsOf: $0, encoding: .utf8) }.joined()
        #expect(text.contains(failure.code.rawValue))
        #expect(text.contains("\"retryCount\":3"))
        let reportPath = try #require(await controller.fatalReportPath())
        #expect(FileManager.default.fileExists(atPath: reportPath))
        let report = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: reportPath))) as? [String: Any]
        #expect(report?["retry_count"] as? Int == 3)
        #expect(report?["error_code"] as? String == failure.code.rawValue)
        #expect(try await session.rows(in: "raw_samples") == 0)
        await controller.stop()
        try await session.closeAndDeleteSession()
    }

    @Test func mismatchedTransportRequestIdentityIsRejected() async throws {
        let profile = try Configuration.bundledProfile()
        let transport = AuditMalformedTransport(catalog: auditCPUCatalog(profile: profile))
        let client = QualifiedSensorClient(transport: transport, registry: ProfileRegistry(profile: profile))
        let catalog = try await client.discover()
        let source = try #require(catalog.available.first)
        do {
            _ = try await client.read(ReadRequest(requestID: RequestID(UUID()), sourceIDs: [source.sourceID], requestedPeriodMS: 200))
            Issue.record("Transport response with a different request identity was accepted")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .sensorProtocol)
            #expect(failure.underlyingCode == "transport_response_identity_mismatch")
        }
    }

    @Test func reconnectCreatesNewSourceAndSeriesIdentities() throws {
        let profile = try Configuration.bundledProfile()
        let raw = auditCPUCatalog(profile: profile)
        let registry = ProfileRegistry(profile: profile)
        let first = try registry.qualify(raw)
        let second = try registry.qualify(DiscoveredCatalog(generation: 2, sources: raw.sources))
        #expect(Set(first.available.map(\.sourceID)).isDisjoint(with: second.available.map(\.sourceID)))
        let firstDefinitions = try SeriesCatalogBuilder.definitions(from: first)
        let secondDefinitions = try SeriesCatalogBuilder.definitions(from: second)
        #expect(Set(firstDefinitions.map(\.seriesID)).isDisjoint(with: secondDefinitions.map(\.seriesID)))
    }

    @Test func firstCPUFailureHasExplicitMainValueFailureState() async throws {
        let fixture = try await ProcessorFixture.make(cpuMembers: 12)
        let id = RequestID(UUID())
        var readings = Fixtures.read(id: id, ms: 200, values: Array(repeating: 70, count: 12)).readings
        readings[0] = Reading(sourceID: SourceID(Fixtures.uuid(1)), started: Fixtures.timestamp(ms: 200), finished: Fixtures.timestamp(ms: 200),
            outcome: .failure(MonitorFailure(code: .sensorRead, severity: .degraded, component: "fixture", operation: "read", retryCount: 0, sourceID: SourceID(Fixtures.uuid(1)), underlyingCode: "io_failed")))
        _ = try await fixture.engine.accept(ReadBatch(requestID: id, generation: 1, requestedPeriodMS: 200, readings: readings), lease: fixture.lease(owner: .request(id), generation: 1))
        let snapshot = await fixture.engine.snapshot(at: Fixtures.timestamp(ms: 200))
        let main = try #require(snapshot.values.first { $0.definition.kind == .cpuMain })
        guard case let .unavailable(capability, reason) = main.state else { Issue.record("failed main metric remained loading"); return }
        #expect(capability == .failed)
        #expect(reason.contains("io_failed"))
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
    private let alwaysFail: Bool
    init(clock: TestClock, catalog: DiscoveredCatalog, alwaysFail: Bool = false) { self.clock = clock; self.catalog = catalog; self.alwaysFail = alwaysFail }
    func discoverRaw() async throws -> DiscoveredCatalog {
        discoverCount += 1
        return DiscoveredCatalog(generation: UInt64(discoverCount), sources: catalog.sources)
    }
    func readRaw(_ request: TransportReadRequest) async throws -> TransportReadBatch {
        readCount += 1
        if alwaysFail || readCount == 1 {
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

private struct AuditMalformedTransport: SensorTransport {
    let catalog: DiscoveredCatalog
    func discoverRaw() async throws -> DiscoveredCatalog { catalog }
    func readRaw(_ request: TransportReadRequest) async throws -> TransportReadBatch {
        let now = Fixtures.timestamp(ms: 200)
        return TransportReadBatch(requestID: RequestID(UUID()), generation: request.generation,
            readings: request.transportHandles.map { TransportReading(transportHandle: $0, started: now, finished: now,
                outcome: .success(valueC: 70, sourceWallUnixNS: nil, freshness: .unknown)) })
    }
    func close() async {}
}
