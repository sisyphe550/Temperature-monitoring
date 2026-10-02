import Foundation
import Testing
@testable import SensorRuntime
@testable import TemperatureCore

@Suite(.serialized) struct HistorySourceContinuityRegressionTests {
    @Test func fiveMinuteHistoryRetainsPriorSourceDefinitionWithoutJoiningSeries() async throws {
        let fixture = try await ProcessorFixture.make()
        let firstID = RequestID(UUID())
        _ = try await fixture.accept(Fixtures.read(id: firstID, ms: 200, values: [50]), lease: fixture.lease(owner: .request(firstID), generation: 1))
        let source = SourceID(Fixtures.uuid(2))
        let newSeries = SeriesID(Fixtures.uuid(202))
        let definition = SeriesDefinition(seriesID: newSeries, metricID: try MetricID(validating: "fixture.cpu"), definitionVersion: 2,
            kind: .cpuZone, displayName: "来源2", memberSourceIDs: [source], formula: .identity)
        await fixture.engine.replaceDefinitions([definition])
        let nextID = RequestID(UUID())
        let next = ReadBatch(requestID: nextID, generation: 2, requestedPeriodMS: 200,
            readings: [Reading(sourceID: source, started: Fixtures.timestamp(ms: 400), finished: Fixtures.timestamp(ms: 400),
                outcome: .success(valueC: 60, sourceWallUnixNS: nil, freshness: .unknown))])
        _ = try await fixture.accept(next, lease: fixture.lease(owner: .request(nextID), generation: 2))
        let request = HistoryRequest(seriesIDs: [fixture.seriesID, newSeries], range: .fiveMinutes, asOfElapsedNS: 500_000_000, pointLimit: 2000)
        let history = await fixture.engine.realtime(request)
        #expect(Set(history.points.map(\.seriesID)) == Set([fixture.seriesID, newSeries]))
        #expect(history.points.contains { $0.seriesID == fixture.seriesID && $0.valueC == 50 })
        #expect(history.points.contains { $0.seriesID == newSeries && $0.valueC == 60 })
        #expect(await fixture.engine.activeSeriesCount() == 1)
        let expired = await fixture.engine.realtime(HistoryRequest(seriesIDs: [fixture.seriesID, newSeries], range: .fiveMinutes,
            asOfElapsedNS: 301_000_000_000, pointLimit: 2000))
        #expect(expired.points.isEmpty)
    }

    @Test func qualifiedUnavailableOptionalCapabilityHasVisibleRowWithoutSamples() async throws {
        let clock = TestClock(now: Fixtures.timestamp(ms: 0))
        let source = QualifiedSource(sourceID: SourceID(Fixtures.uuid(10)), transportHandle: "fixture:cpu", provider: .smc,
            rawKey: "Tp01", registryID: nil, connectionGeneration: 1, kind: .cpuZone, encoding: "flt ", unitEvidence: "fixture",
            evidence: .targetQualified, mappingVersion: "test-v1")
        let catalog = QualifiedSourceCatalog(generation: 1, available: [source], unavailable: [SourceCapabilityRecord(provider: .nvme,
            rawKey: nil, registryID: nil, intendedKind: .ssd, capability: .unsupported, reason: "smart_temperature_not_reported")])
        let client = ScriptableSensorClient(clock: clock, catalog: catalog)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("UnavailableRow-\(UUID())")
        let session = SessionPersistenceActor(databaseURL: root.appendingPathComponent("monitor.sqlite"))
        let controller = SessionMonitorController(clock: clock, client: client, session: session,
            sessionMetadata: SessionMetadata(sessionID: SessionID(UUID()), startedWallUnixNS: 1, model: "Mac16,13", osBuild: "fixture", appVersion: "test"),
            configuration: try Configuration.bundledDefaults())
        try await controller.start()
        let stream = await controller.snapshots()
        var iterator = stream.makeAsyncIterator()
        let snapshot = try #require(await iterator.next())
        let row = try #require(snapshot.values.first { $0.definition.kind == .ssd })
        #expect(row.state == .unavailable(capability: .unsupported, reason: "smart_temperature_not_reported"))
        #expect(row.definition.memberSourceIDs.isEmpty)
        #expect(try await session.rows(in: "raw_samples") == 0)
        await controller.stop()
    }
}
