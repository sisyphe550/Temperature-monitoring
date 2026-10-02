import Foundation
import Testing
@testable import SensorRuntime
@testable import TemperatureCore

// A software fault fixture; it does not qualify hardware.
@Suite(.serialized) struct RecoveredSourceGapRegressionTests {
    @Test func recoveredTimeoutClosesOldGenerationGapsBeforeInstallingNewSources() async throws {
        let profile = try Configuration.bundledProfile()
        let configuration = try Configuration.bundledDefaults()
        let clock = TestClock(now: Fixtures.timestamp(ms: 0))
        let raw = DiscoveredCatalog(generation: 1, sources: profile.cpuKeys.map { key in
            DiscoveredSource(transportHandle: "smc:\(key)", provider: .smc, rawKey: key,
                registryID: "review-\(key)", encoding: profile.expectedSMCEncoding, byteCount: profile.expectedSMCSizeBytes)
        })
        let transport = RecoveredGapTransport(clock: clock, catalog: raw)
        let client = QualifiedSensorClient(transport: transport, registry: ProfileRegistry(profile: profile))
        let catalog = try await client.discover()
        let definitions = try SeriesCatalogBuilder.definitions(from: catalog)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RecoveredSourceGap-\(UUID())")
        let session = SessionPersistenceActor(databaseURL: directory.appendingPathComponent("monitor.sqlite"))
        let metadata = SessionMetadata(sessionID: SessionID(UUID()), startedWallUnixNS: 1, model: "Mac16,13", osBuild: "24G419", appVersion: "review")
        try await session.open(metadata)
        let engine = MonitorEngine(clock: clock, commit: await session.commitCapability(), session: metadata,
            configuration: configuration, definitions: definitions, cpuPeriodMS: 200,
            qualifiedSources: catalog.available, sessionStartedAt: clock.now())
        let coordinator = ProcessingCoordinator(clock: clock, client: client, reservation: await session.reservationCapability(),
            engine: engine, configuration: configuration)
        await coordinator.start(catalog: catalog)
        for ms in stride(from: Int64(200), through: Int64(2000), by: 20) {
            clock.advance(to: Fixtures.timestamp(ms: ms))
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        await coordinator.stop()
        #expect(await transport.readCount > 1)
        #expect(await coordinator.lastAcceptFailure == nil)
        let snapshot = await engine.snapshot(at: clock.now())
        #expect(snapshot.values.allSatisfy { $0.definition.definitionVersion == 2 })
        #expect(snapshot.values.contains { value in if case .available = value.state { return true }; return false })
        #expect(snapshot.gapIDs.isEmpty, "Successful generation 2 must not keep generation 1 gaps open forever")
        let oldMaximum = try #require(definitions.first { $0.kind == .cpuMain })
        let oldZone = try #require(definitions.first { $0.kind == .cpuZone })
        let history = try await session.query(HistoryRequest(seriesIDs: [oldMaximum.seriesID, oldZone.seriesID], range: .oneHour,
            asOfElapsedNS: clock.now().elapsedNS, pointLimit: 100))
        #expect(history.gaps.count == 2)
        #expect(history.gaps.allSatisfy { $0.endedElapsedNS != nil && $0.reason == .timeout })
        #expect(try await session.rows(in: "sources") == 24)
        try await session.closeAndDeleteSession()
    }
}

private actor RecoveredGapTransport: SensorTransport {
    let clock: TestClock
    let catalog: DiscoveredCatalog
    private(set) var readCount = 0
    private var discoverCount = 0
    init(clock: TestClock, catalog: DiscoveredCatalog) { self.clock = clock; self.catalog = catalog }
    func discoverRaw() async throws -> DiscoveredCatalog {
        discoverCount += 1
        return DiscoveredCatalog(generation: UInt64(discoverCount), sources: catalog.sources)
    }
    func readRaw(_ request: TransportReadRequest) async throws -> TransportReadBatch {
        readCount += 1
        if readCount == 1 {
            throw MonitorFailure(code: .sensorTimeout, severity: .degraded, component: "RecoveredGapTransport", operation: "read",
                retryCount: 0, sourceID: nil, underlyingCode: "single_timeout")
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
