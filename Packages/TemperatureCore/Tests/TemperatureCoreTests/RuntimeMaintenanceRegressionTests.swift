import Foundation
import Testing
@testable import TemperatureCore
@testable import SensorRuntime

@Suite(.serialized) struct RuntimeMaintenanceRegressionTests {
    @Test func runningControllerPrunesExpiredRawWithCommittedParentWithoutSleep() async throws {
        let fixture = try await ControllerFixture.make()
        try await fixture.controller.start()
        _ = try await fixture.session.appendForTesting(Fixtures.persistence(id: BatchID(UUID()), value: 50, ms: 0))
        let seriesID = SeriesID(Fixtures.uuid(101))
        let bucket = Bucket(seriesID: seriesID, segment: 1, widthSeconds: 1, startElapsedNS: 0, endElapsedNS: 1_000_000_000,
            minC: 50, maxC: 50, sumC: 50, count: 1, latestC: 50, latestElapsedNS: 0,
            latestSampleID: "sample-0", isPartial: true, coverageNS: 200_000_000)
        _ = try await fixture.session.appendForTesting(PersistenceBatch(batchID: BatchID(UUID()), sources: [], definitions: [],
            segments: [], raw: [], ema: [], buckets: [bucket], trends: [], gaps: []))
        #expect(try await fixture.session.rows(in: "raw_samples") == 1)
        fixture.clock.advance(to: Fixtures.timestamp(ms: 481_000))
        for _ in 0..<50 {
            if try await fixture.session.rows(in: "raw_samples") == 0 { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(try await fixture.session.rows(in: "raw_samples") == 0)
        #expect(try await fixture.session.rows(in: "ema_samples") == 0)
        #expect(await fixture.controller.lastAcceptFailure() == nil)
        await fixture.controller.stop()
        try await fixture.closeAndDeleteSession()
    }

    @Test func expiredRequestCannotBeReintroducedAsNewTemperature() async throws {
        let fixture = try await ProcessorFixture.make()
        let firstID = RequestID(UUID())
        let first = Fixtures.read(id: firstID, ms: 200, values: [50])
        _ = try await fixture.accept(first, lease: fixture.lease(owner: .request(firstID), generation: 1))
        let nextID = RequestID(UUID())
        let next = Fixtures.read(id: nextID, ms: 700_000, values: [60])
        _ = try await fixture.accept(next, lease: fixture.lease(owner: .request(nextID), generation: 1))
        do {
            _ = try await fixture.engine.accept(first, lease: fixture.lease(owner: .request(firstID), generation: 1))
            Issue.record("An expired request was accepted after its bounded replay cache lifetime")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .processingValidate)
            #expect(failure.underlyingCode == "expired_request")
        }
        #expect((await fixture.rawSamples(nowMS: 700_000)).count == 1)
        #expect(await fixture.engine.replayCacheCountForTesting() == 1)
    }
}
