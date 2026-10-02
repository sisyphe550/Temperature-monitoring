import Foundation
import Testing
@testable import TemperatureCore
@testable import SensorRuntime

@Suite(.serialized) struct RuntimeShutdownRegressionTests {
    @Test func fatalFreezeStopsIOButPreservesDatabaseUntilQuit() async throws {
        let fixture = try await ControllerFixture.make()
        try await fixture.controller.start()
        fixture.clock.advance(to: Fixtures.timestamp(ms: 200))
        for _ in 0..<200 {
            if await fixture.client.readCount > 0 { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(await fixture.client.readCount == 1)
        await fixture.controller.freezeForFatal()
        let readCount = await fixture.client.readCount
        #expect(await fixture.session.openedSessionMetadata != nil)
        fixture.clock.advance(to: Fixtures.timestamp(ms: 120_000))
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(await fixture.client.readCount == readCount)
        await fixture.controller.stop()
        #expect(await fixture.session.openedSessionMetadata == nil)
        #expect(await fixture.controller.lastShutdownOutcome()?.incompleteSteps.isEmpty == true)
    }

    @Test func stopWaitsForSessionDeletionAndIsIdempotent() async throws {
        let clock = TestClock(now: Fixtures.timestamp(ms: 0))
        let source = QualifiedSource(sourceID: SourceID(Fixtures.uuid(10)), transportHandle: "fixture:cpu", provider: .smc,
            rawKey: "Tp01", registryID: nil, connectionGeneration: 1, kind: .cpuZone, encoding: "flt ", unitEvidence: "fixture",
            evidence: .targetQualified, mappingVersion: "test-v1")
        let client = ScriptableSensorClient(clock: clock, catalog: QualifiedSourceCatalog(generation: 1, available: [source], unavailable: []))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AwaitedStop-\(UUID())")
        let database = root.appendingPathComponent("monitor.sqlite")
        let session = SessionPersistenceActor(databaseURL: database)
        let controller = SessionMonitorController(clock: clock, client: client, session: session,
            sessionMetadata: SessionMetadata(sessionID: SessionID(UUID()), startedWallUnixNS: 1, model: "Mac16,13", osBuild: "fixture", appVersion: "test"),
            configuration: try Configuration.bundledDefaults())
        try await controller.start()
        #expect(FileManager.default.fileExists(atPath: database.path))
        async let first: Void = controller.stop()
        async let second: Void = controller.stop()
        _ = await (first, second)
        #expect(!FileManager.default.fileExists(atPath: database.path))
        #expect(!FileManager.default.fileExists(atPath: database.path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: database.path + "-shm"))
        let result = try #require(await controller.lastShutdownOutcome())
        #expect(result.incompleteSteps.isEmpty)
        #expect(result.stepResults.contains { $0.name == "close_and_delete_session" && $0.completed })
    }
}
