import Foundation
import Testing
@testable import TemperatureCore

@Suite struct AggregationTests {
    @Test func oneSecondWindowAggregatesRawSamples() {
        var engine = AggregationEngine()
        let seriesID = SeriesID(Fixtures.uuid(101))
        let points: [(Int64, Double)] = [(100, 70.0), (200, 71.0), (300, 72.0), (400, 95.0), (500, 74.0)]
        for (ms, value) in points {
            engine.ingest(
                sample(
                    id: "fixture-session:\(ms)",
                    seriesID: seriesID,
                    segment: 1,
                    ms: ms,
                    value: value
                )
            )
        }

        let closed = engine.advance(to: 1_000_000_000)
        #expect(closed.count == 1)
        let bucket = closed[0]
        #expect(bucket.minC == 70)
        #expect(bucket.maxC == 95)
        #expect(bucket.sumC == 382)
        #expect(bucket.count == 5)
        #expect(bucket.latestC == 74)
        #expect(abs((bucket.sumC / Double(bucket.count)) - 76.4) < 1e-9)
    }

    @Test func parentMergeUsesWeightedAverage() {
        let seriesID = SeriesID(Fixtures.uuid(101))
        let bucketA = Bucket(
            seriesID: seriesID,
            segment: 1,
            widthSeconds: 1,
            startElapsedNS: 0,
            endElapsedNS: 1_000_000_000,
            minC: 60,
            maxC: 60,
            sumC: 60,
            count: 1,
            latestC: 60,
            latestElapsedNS: 100_000_000,
            latestSampleID: "a",
            isPartial: false,
            coverageNS: 200_000_000
        )
        let bucketB = Bucket(
            seriesID: seriesID,
            segment: 1,
            widthSeconds: 1,
            startElapsedNS: 1_000_000_000,
            endElapsedNS: 2_000_000_000,
            minC: 80,
            maxC: 80,
            sumC: 240,
            count: 3,
            latestC: 80,
            latestElapsedNS: 1_500_000_000,
            latestSampleID: "b",
            isPartial: false,
            coverageNS: 600_000_000
        )

        let merged = BucketMerger.merge(
            children: [bucketA, bucketB],
            widthSeconds: 10,
            startElapsedNS: 0,
            endElapsedNS: 10_000_000_000
        )
        guard let result = merged else {
            Issue.record("expected merged bucket")
            return
        }
        #expect(result.sumC == 300)
        #expect(result.count == 4)
        #expect(abs((result.sumC / Double(result.count)) - 75) < 1e-9)
    }

    @Test func pointExactlyOnBoundaryGoesToNextWindow() {
        var engine = AggregationEngine()
        let seriesID = SeriesID(Fixtures.uuid(101))
        engine.ingest(
            sample(id: "fixture-session:0", seriesID: seriesID, segment: 1, ms: 999, value: 70)
        )
        engine.ingest(
            sample(id: "fixture-session:1", seriesID: seriesID, segment: 1, ms: 1000, value: 80)
        )

        let firstClose = engine.advance(to: 1_000_000_000)
        #expect(firstClose.count == 1)
        #expect(firstClose[0].latestC == 70)

        let secondClose = engine.advance(to: 2_000_000_000)
        #expect(secondClose.count == 1)
        #expect(secondClose[0].latestC == 80)
        #expect(secondClose[0].startElapsedNS == 1_000_000_000)
    }

    @Test func emptyWindowProducesNoBucket() {
        var engine = AggregationEngine()
        let closed = engine.advance(to: 3_000_000_000)
        #expect(closed.isEmpty)
    }

    @Test func sparseTenSecondWindowClosesPartial() {
        var engine = AggregationEngine()
        let seriesID = SeriesID(Fixtures.uuid(101))
        engine.ingest(sample(id: "s0", seriesID: seriesID, segment: 1, ms: 0, value: 70))
        engine.ingest(sample(id: "s9", seriesID: seriesID, segment: 1, ms: 9000, value: 80))

        let closed = engine.advance(to: 10_000_000_000)
        let oneSecond = closed.filter { $0.widthSeconds == 1 }
        guard let tenSecond = closed.first(where: { $0.widthSeconds == 10 }) else {
            Issue.record("expected 10s bucket")
            return
        }
        #expect(oneSecond.count == 2)
        #expect(tenSecond.isPartial)
        #expect(tenSecond.count == 2)
        #expect(tenSecond.minC == 70)
        #expect(tenSecond.maxC == 80)
    }

    @Test func sameSecondSegmentChangeKeepsBucketsSeparate() {
        var engine = AggregationEngine()
        let seriesID = SeriesID(Fixtures.uuid(101))
        engine.ingest(sample(id: "seg1", seriesID: seriesID, segment: 1, ms: 100, value: 70))
        engine.ingest(sample(id: "seg2", seriesID: seriesID, segment: 2, ms: 100, value: 80))

        let closed = engine.advance(to: 1_000_000_000)
        #expect(closed.count == 2)
        #expect(Set(closed.map(\.segment)) == Set([1, 2]))
    }

    @Test func inFlightRequestDefersWindowClosure() {
        var engine = AggregationEngine()
        let seriesID = SeriesID(Fixtures.uuid(101))
        engine.beginInFlight(startElapsedNS: [0])
        engine.ingest(sample(id: "s1", seriesID: seriesID, segment: 1, ms: 100, value: 70))

        #expect(engine.advance(to: 1_000_000_000).isEmpty)

        engine.endInFlight(startElapsedNS: [0])
        let closed = engine.advance(to: 1_000_000_000)
        #expect(closed.count == 1)
    }

    @Test func integrationAdvancePersistsBuckets() async throws {
        let fixture = try await ProcessorFixture.make()
        let requestID = RequestID(Fixtures.uuid(601))
        _ = try await fixture.accept(
            Fixtures.read(id: requestID, ms: 100, values: [70]),
            lease: fixture.lease(owner: .request(requestID), generation: 1)
        )

        let watermarkID = WatermarkEventID(Fixtures.uuid(602))
        let advanceLease = fixture.lease(owner: .watermark(watermarkID), generation: 1)
        let receipt = try await fixture.advance(toMS: 1000, lease: advanceLease)
        let batch = try #require(await fixture.committedBatch(for: receipt))
        #expect(batch.buckets.count == 1)
        #expect(batch.buckets[0].count == 1)
        #expect(batch.buckets[0].latestC == 70)
    }
}

private func sample(
    id: String,
    seriesID: SeriesID,
    segment: Int64,
    ms: Int64,
    value: Double
) -> Sample {
    Sample(
        sampleID: id,
        seriesID: seriesID,
        segment: segment,
        timestamp: Fixtures.timestamp(ms: ms),
        periodMS: 200,
        valueC: value,
        freshness: .unknown,
        sourceWallUnixNS: nil,
        memberSampleIDs: []
    )
}
