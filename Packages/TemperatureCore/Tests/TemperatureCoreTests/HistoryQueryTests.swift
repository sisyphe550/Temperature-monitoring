import Foundation
import Testing
@testable import TemperatureCore

@Suite struct HistoryQueryTests {
    @Test func returnsEmptyResultWhenNoData() async throws {
        let fixture = try await TemporaryStoreFixture.make()
        let seriesID = SeriesID(Fixtures.uuid(101))
        let result = try await fixture.session.query(
            HistoryRequest(
                seriesIDs: [seriesID],
                range: .oneDay,
                asOfElapsedNS: 86_400_000_000_000,
                pointLimit: 2000
            )
        )
        #expect(result.layer == .tenSeconds)
        #expect(result.points.isEmpty)
        try await fixture.closeAndDeleteSession()
    }

    @Test func rejectsFiveMinuteSQLiteRange() async throws {
        let fixture = try await TemporaryStoreFixture.make()
        do {
            _ = try await fixture.session.query(
                HistoryRequest(
                    seriesIDs: [SeriesID(Fixtures.uuid(101))],
                    range: .fiveMinutes,
                    asOfElapsedNS: 300_000_000_000,
                    pointLimit: 100
                )
            )
            Issue.record("expected unsupported range")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .databaseRead)
        }
        try await fixture.closeAndDeleteSession()
    }

    @Test func rejectsMoreThanEightSeries() async throws {
        let fixture = try await TemporaryStoreFixture.make()
        let seriesIDs = (1...9).map { SeriesID(Fixtures.uuid($0)) }
        do {
            _ = try await fixture.session.query(
                HistoryRequest(
                    seriesIDs: seriesIDs,
                    range: .oneHour,
                    asOfElapsedNS: 3_600_000_000_000,
                    pointLimit: 100
                )
            )
            Issue.record("expected too many series")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .databaseRead)
        }
        try await fixture.closeAndDeleteSession()
    }

    @Test func downsamplingPreservesPeakAcross8640Buckets() async throws {
        let fixture = try await TemporaryStoreFixture.make()
        let seriesID = SeriesID(Fixtures.uuid(101))
        let setup = try Fixtures.persistence(id: BatchID(Fixtures.uuid(401)), value: 50, ms: 0)
        _ = try await fixture.appendForTesting(setup)

        let peakIndex = 4320
        try await insertTenSecondBuckets(
            fixture: fixture,
            seriesID: seriesID,
            peakIndex: peakIndex,
            peakMax: 99,
            baselineMax: 50
        )

        let asOf = Int64(8640) * 10 * 1_000_000_000
        let result = try await fixture.session.query(
            HistoryRequest(
                seriesIDs: [seriesID],
                range: .oneDay,
                asOfElapsedNS: asOf,
                pointLimit: 2000
            )
        )

        #expect(result.points.count <= 2000)
        #expect(result.points.count > 0)
        let globalMax = result.points.compactMap(\.maxC).max()
        #expect(globalMax == 99)
        if let first = result.points.min(by: { $0.elapsedNS < $1.elapsedNS }),
           let last = result.points.max(by: { $0.elapsedNS < $1.elapsedNS })
        {
            #expect(first.elapsedNS < last.elapsedNS)
        }
        try await fixture.closeAndDeleteSession()
    }

    @Test func keepsSegmentsSeparateInResults() async throws {
        let fixture = try await TemporaryStoreFixture.make()
        let seriesID = SeriesID(Fixtures.uuid(101))
        let setup = try Fixtures.persistence(id: BatchID(Fixtures.uuid(402)), value: 50, ms: 0)
        _ = try await fixture.appendForTesting(setup)

        let segmentTwo = PersistenceBatch(
            batchID: BatchID(Fixtures.uuid(403)),
            sources: [],
            definitions: [],
            segments: [
                Segment(
                    seriesID: seriesID,
                    number: 2,
                    started: Timestamp(elapsedNS: 500_000_000_000, wallUnixNS: 1),
                    reason: .wake
                )
            ],
            raw: [],
            ema: [],
            buckets: [
                Bucket(
                    seriesID: seriesID,
                    segment: 2,
                    widthSeconds: 10,
                    startElapsedNS: 500_000_000_000,
                    endElapsedNS: 510_000_000_000,
                    minC: 60,
                    maxC: 60,
                    sumC: 60,
                    count: 1,
                    latestC: 60,
                    latestElapsedNS: 505_000_000_000,
                    latestSampleID: "seg2",
                    isPartial: false,
                    coverageNS: 10_000_000_000
                )
            ],
            trends: [],
            gaps: []
        )
        _ = try await fixture.appendForTesting(segmentTwo)

        let segmentOneBucket = PersistenceBatch(
            batchID: BatchID(Fixtures.uuid(404)),
            sources: [],
            definitions: [],
            segments: [],
            raw: [],
            ema: [],
            buckets: [
                Bucket(
                    seriesID: seriesID,
                    segment: 1,
                    widthSeconds: 10,
                    startElapsedNS: 100_000_000_000,
                    endElapsedNS: 110_000_000_000,
                    minC: 50,
                    maxC: 50,
                    sumC: 50,
                    count: 1,
                    latestC: 50,
                    latestElapsedNS: 105_000_000_000,
                    latestSampleID: "seg1",
                    isPartial: false,
                    coverageNS: 10_000_000_000
                )
            ],
            trends: [],
            gaps: []
        )
        _ = try await fixture.appendForTesting(segmentOneBucket)

        let result = try await fixture.session.query(
            HistoryRequest(
                seriesIDs: [seriesID],
                range: .oneDay,
                asOfElapsedNS: 86_400_000_000_000,
                pointLimit: 2000
            )
        )

        let segments = Set(result.points.map(\.segment))
        #expect(segments.contains(1))
        #expect(segments.contains(2))
        try await fixture.closeAndDeleteSession()
    }

    @Test func supersededQueryIsDiscarded() async throws {
        let fixture = try await TemporaryStoreFixture.make()
        let seriesID = SeriesID(Fixtures.uuid(101))
        let setup = try Fixtures.persistence(id: BatchID(Fixtures.uuid(405)), value: 50, ms: 0)
        _ = try await fixture.appendForTesting(setup)
        try await insertTenSecondBuckets(
            fixture: fixture,
            seriesID: seriesID,
            peakIndex: 100,
            peakMax: 70,
            baselineMax: 50
        )

        async let first = fixture.session.query(
            HistoryRequest(
                seriesIDs: [seriesID],
                range: .oneDay,
                asOfElapsedNS: Int64(8640) * 10 * 1_000_000_000,
                pointLimit: 2000
            )
        )
        async let second = fixture.session.query(
            HistoryRequest(
                seriesIDs: [seriesID],
                range: .oneHour,
                asOfElapsedNS: 100_000_000_000,
                pointLimit: 100
            )
        )

        do {
            _ = try await first
            Issue.record("expected superseded query failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .databaseRead)
            #expect(failure.underlyingCode == "superseded")
        }

        let latest = try await second
        #expect(latest.layer == .oneSecond)
        try await fixture.closeAndDeleteSession()
    }
}

private func insertTenSecondBuckets(
    fixture: TemporaryStoreFixture,
    seriesID: SeriesID,
    peakIndex: Int,
    peakMax: Double,
    baselineMax: Double
) async throws {
    let chunkSize = 200
    var batchOrdinal = 500
    for startIndex in stride(from: 0, to: 8640, by: chunkSize) {
        var buckets: [Bucket] = []
        buckets.reserveCapacity(chunkSize)
        for offset in 0..<chunkSize {
            let index = startIndex + offset
            if index >= 8640 { break }
            let start = Int64(index) * 10 * 1_000_000_000
            let end = start + 10 * 1_000_000_000
            let maxValue = index == peakIndex ? peakMax : baselineMax
            buckets.append(
                Bucket(
                    seriesID: seriesID,
                    segment: 1,
                    widthSeconds: 10,
                    startElapsedNS: start,
                    endElapsedNS: end,
                    minC: maxValue - 1,
                    maxC: maxValue,
                    sumC: maxValue,
                    count: 1,
                    latestC: maxValue,
                    latestElapsedNS: start + 5 * 1_000_000_000,
                    latestSampleID: "bucket-\(index)",
                    isPartial: false,
                    coverageNS: 10_000_000_000
                )
            )
        }
        let batch = PersistenceBatch(
            batchID: BatchID(Fixtures.uuid(batchOrdinal)),
            sources: [],
            definitions: [],
            segments: [],
            raw: [],
            ema: [],
            buckets: buckets,
            trends: [],
            gaps: []
        )
        batchOrdinal += 1
        _ = try await fixture.appendForTesting(batch)
    }
}
