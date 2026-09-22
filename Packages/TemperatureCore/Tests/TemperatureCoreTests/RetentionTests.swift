import Foundation
import Testing
@testable import TemperatureCore

@Suite struct RetentionTests {
    @Test func deletesAggregateExactlyAtCutoff() async throws {
        let fixture = try await TemporaryStoreFixture.make()
        let seriesID = SeriesID(Fixtures.uuid(101))
        let setup = try Fixtures.persistence(id: BatchID(Fixtures.uuid(501)), value: 50, ms: 0)
        _ = try await fixture.appendForTesting(setup)
        _ = try await fixture.appendForTesting(
            oneSecondParentBatch(
                batchID: BatchID(Fixtures.uuid(5011)),
                seriesID: seriesID,
                endElapsedNS: seconds(1)
            )
        )

        let nowSeconds: Int64 = 90_000
        let atCutoff = try bucketBatch(
            batchID: BatchID(Fixtures.uuid(502)),
            seriesID: seriesID,
            endElapsedNS: cutoffElapsed(nowSeconds: nowSeconds, retentionSeconds: 86_400)
        )
        let afterCutoff = try bucketBatch(
            batchID: BatchID(Fixtures.uuid(503)),
            seriesID: seriesID,
            endElapsedNS: cutoffElapsed(nowSeconds: nowSeconds, retentionSeconds: 86_400) + 1
        )
        _ = try await fixture.appendForTesting(atCutoff)
        _ = try await fixture.appendForTesting(afterCutoff)

        try await fixture.session.prune(nowElapsedNS: seconds(nowSeconds))

        #expect(try await fixture.rows(in: "aggregates") == 1)
        try await fixture.closeAndDeleteSession()
    }

    @Test func retainsRawWithoutOneSecondParent() async throws {
        let fixture = try await TemporaryStoreFixture.make()
        let seriesID = SeriesID(Fixtures.uuid(101))
        let setup = try Fixtures.persistence(id: BatchID(Fixtures.uuid(504)), value: 50, ms: 0)
        _ = try await fixture.appendForTesting(setup)

        let orphanRaw = PersistenceBatch(
            batchID: BatchID(Fixtures.uuid(505)),
            sources: [],
            definitions: [],
            segments: [],
            raw: [
                Sample(
                    sampleID: "orphan-raw",
                    seriesID: seriesID,
                    segment: 1,
                    timestamp: Timestamp(elapsedNS: seconds(50), wallUnixNS: 1),
                    periodMS: 200,
                    valueC: 50,
                    freshness: .unknown,
                    sourceWallUnixNS: nil,
                    memberSampleIDs: []
                )
            ],
            ema: [],
            buckets: [],
            trends: [],
            gaps: []
        )
        _ = try await fixture.appendForTesting(orphanRaw)

        try await fixture.session.prune(nowElapsedNS: seconds(400))

        #expect(try await fixture.rows(in: "raw_samples") == 2)
        try await fixture.closeAndDeleteSession()
    }

    @Test func pruneAfterLongSleepRemovesExpiredRows() async throws {
        let fixture = try await TemporaryStoreFixture.make()
        let setup = try Fixtures.persistence(id: BatchID(Fixtures.uuid(506)), value: 50, ms: 0)
        _ = try await fixture.appendForTesting(setup)
        _ = try await fixture.appendForTesting(
            oneSecondParentBatch(
                batchID: BatchID(Fixtures.uuid(5061)),
                seriesID: SeriesID(Fixtures.uuid(101)),
                endElapsedNS: seconds(1)
            )
        )

        let oldBucket = try bucketBatch(
            batchID: BatchID(Fixtures.uuid(507)),
            seriesID: SeriesID(Fixtures.uuid(101)),
            endElapsedNS: seconds(100)
        )
        _ = try await fixture.appendForTesting(oldBucket)

        try await fixture.session.prune(nowElapsedNS: seconds(300_000))

        #expect(try await fixture.rows(in: "aggregates") == 0)
        let result = try await fixture.session.query(
            HistoryRequest(
                seriesIDs: [SeriesID(Fixtures.uuid(101))],
                range: .threeDays,
                asOfElapsedNS: seconds(300_000),
                pointLimit: 100
            )
        )
        #expect(result.points.isEmpty)
        try await fixture.closeAndDeleteSession()
    }

    @Test func cleanupGraceExceededIsFatal() async throws {
        let policy = RetentionPolicy(
            retention: RetentionSeconds(
                raw: 300,
                ema: 300,
                oneSecond: 3600,
                tenSeconds: 86400,
                oneMinute: 259_200,
                trend: 3600
            ),
            graceSeconds: 120,
            dbSoftBytes: 805_306_368,
            dbHardBytes: 1_073_741_824,
            walSoftBytes: 33_554_432,
            walHardBytes: 67_108_864
        )
        let fixture = try await TemporaryStoreFixture.make(retentionPolicy: policy)
        let setup = try Fixtures.persistence(id: BatchID(Fixtures.uuid(508)), value: 50, ms: 0)
        _ = try await fixture.appendForTesting(setup)

        let orphanRaw = PersistenceBatch(
            batchID: BatchID(Fixtures.uuid(509)),
            sources: [],
            definitions: [],
            segments: [],
            raw: [
                Sample(
                    sampleID: "stale-orphan-raw",
                    seriesID: SeriesID(Fixtures.uuid(101)),
                    segment: 1,
                    timestamp: Timestamp(elapsedNS: seconds(10), wallUnixNS: 1),
                    periodMS: 200,
                    valueC: 50,
                    freshness: .unknown,
                    sourceWallUnixNS: nil,
                    memberSampleIDs: []
                )
            ],
            ema: [],
            buckets: [],
            trends: [],
            gaps: []
        )
        _ = try await fixture.appendForTesting(orphanRaw)

        do {
            try await fixture.session.prune(nowElapsedNS: seconds(500))
            Issue.record("expected cleanup grace failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .databaseClean)
            #expect(failure.underlyingCode == "grace_exceeded")
        }
        try await fixture.closeAndDeleteSession()
    }
}

private func seconds(_ value: Int64) -> Int64 {
    value * 1_000_000_000
}

private func cutoffElapsed(nowSeconds: Int64, retentionSeconds: Int64) -> Int64 {
    seconds(nowSeconds - retentionSeconds)
}

private func oneSecondParentBatch(
    batchID: BatchID,
    seriesID: SeriesID,
    endElapsedNS: Int64
) -> PersistenceBatch {
    let width: Int64 = 1_000_000_000
    let start = endElapsedNS - width
    return PersistenceBatch(
        batchID: batchID,
        sources: [],
        definitions: [],
        segments: [],
        raw: [],
        ema: [],
        buckets: [
            Bucket(
                seriesID: seriesID,
                segment: 1,
                widthSeconds: 1,
                startElapsedNS: start,
                endElapsedNS: endElapsedNS,
                minC: 50,
                maxC: 50,
                sumC: 50,
                count: 1,
                latestC: 50,
                latestElapsedNS: endElapsedNS - 1,
                latestSampleID: "parent-\(batchID.rawValue)",
                isPartial: false,
                coverageNS: width
            )
        ],
        trends: [],
        gaps: []
    )
}

private func bucketBatch(
    batchID: BatchID,
    seriesID: SeriesID,
    endElapsedNS: Int64
) throws -> PersistenceBatch {
    let width: Int64 = 10 * 1_000_000_000
    let start = endElapsedNS - width
    return PersistenceBatch(
        batchID: batchID,
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
                startElapsedNS: start,
                endElapsedNS: endElapsedNS,
                minC: 50,
                maxC: 50,
                sumC: 50,
                count: 1,
                latestC: 50,
                latestElapsedNS: endElapsedNS - 1,
                latestSampleID: "bucket-\(batchID.rawValue)",
                isPartial: false,
                coverageNS: width
            )
        ],
        trends: [],
        gaps: []
    )
}
