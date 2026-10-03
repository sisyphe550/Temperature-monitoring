import Foundation
import Testing
@testable import TemperatureCore
@testable import SensorRuntime

@Suite(.serialized) struct RuntimeMaintenanceRegressionTests {
    @Test func runningControllerExecutesRetentionAtSixtySecondBoundaries() async throws {
        let fixture = try await ControllerFixture.make()
        // Preserve production TTLs. Starting the clock at 300 s lets legal,
        // nonnegative sample timestamps expire at the first two maintenance ticks.
        fixture.clock.advance(to: Fixtures.timestamp(ms: 300_000))
        try await fixture.controller.start()
        do {
            let setup = try Fixtures.persistence(id: BatchID(UUID()), value: 50, ms: 0)
            let seriesID = SeriesID(Fixtures.uuid(101))
            let second = Sample(
                sampleID: "maintenance-second", seriesID: seriesID, segment: 1,
                timestamp: Fixtures.timestamp(ms: 60_001), periodMS: 200, valueC: 50,
                freshness: .unknown, sourceWallUnixNS: nil, memberSampleIDs: []
            )
            let raw = setup.raw + [second]
            let parents = raw.map { sample in
                let start = (sample.timestamp.elapsedNS / 1_000_000_000) * 1_000_000_000
                return Bucket(
                    seriesID: sample.seriesID, segment: sample.segment, widthSeconds: 1,
                    startElapsedNS: start, endElapsedNS: start + 1_000_000_000,
                    minC: sample.valueC, maxC: sample.valueC, sumC: sample.valueC, count: 1,
                    latestC: sample.valueC, latestElapsedNS: sample.timestamp.elapsedNS,
                    latestSampleID: sample.sampleID, isPartial: true, coverageNS: 200_000_000
                )
            }
            _ = try await fixture.session.appendForTesting(PersistenceBatch(
                batchID: setup.batchID, sources: setup.sources, definitions: setup.definitions,
                segments: setup.segments, raw: raw,
                ema: setup.ema + [EMAValue(sampleID: second.sampleID, seriesID: seriesID,
                    segment: 1, timestamp: second.timestamp, valueC: second.valueC)],
                buckets: parents, trends: [], gaps: []
            ))
            #expect(try await fixture.session.rows(in: "raw_samples") == 2)
            #expect(try await fixture.session.rows(in: "ema_samples") == 2)
            #expect(try await fixture.session.rows(in: "aggregates") == 2)

            // The waiter is a synchronization barrier, not the execution evidence.
            try #require(await waitForRetentionCondition {
                fixture.clock.pendingSleepDeadlinesForTesting.contains(360_000_000_000)
            })
            fixture.clock.advance(to: Fixtures.timestamp(ms: 359_999)) // start + 59.999 s
            #expect(try await fixture.session.rows(in: "raw_samples") == 2)
            #expect(try await fixture.session.rows(in: "ema_samples") == 2)

            fixture.clock.advance(to: Fixtures.timestamp(ms: 360_000)) // start + 60 s
            try #require(await waitForRetentionCondition {
                let rawCount = try await fixture.session.rows(in: "raw_samples")
                let emaCount = try await fixture.session.rows(in: "ema_samples")
                return rawCount == 1 && emaCount == 1
            })
            // Do not advance again until the completed prune has rearmed its loop.
            try #require(await waitForRetentionCondition {
                fixture.clock.pendingSleepDeadlinesForTesting.contains(420_000_000_000)
            })

            fixture.clock.advance(to: Fixtures.timestamp(ms: 419_999)) // start + 119.999 s
            #expect(try await fixture.session.rows(in: "raw_samples") == 1)
            #expect(try await fixture.session.rows(in: "ema_samples") == 1)
            fixture.clock.advance(to: Fixtures.timestamp(ms: 420_000)) // start + 120 s
            try #require(await waitForRetentionCondition {
                let rawCount = try await fixture.session.rows(in: "raw_samples")
                let emaCount = try await fixture.session.rows(in: "ema_samples")
                return rawCount == 0 && emaCount == 0
            })
            #expect(await fixture.controller.lastAcceptFailure() == nil)
        } catch {
            await fixture.controller.stop()
            try? await fixture.closeAndDeleteSession()
            throw error
        }
        await fixture.controller.stop()
        try await fixture.closeAndDeleteSession()
    }

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

private func waitForRetentionCondition(_ condition: () async throws -> Bool) async throws -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while ContinuousClock.now < deadline {
        if try await condition() { return true }
        try await Task.sleep(for: .milliseconds(5))
    }
    return try await condition()
}
