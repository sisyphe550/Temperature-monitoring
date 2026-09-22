import Foundation
import Testing
@testable import TemperatureCore

@Suite struct StorageFaultTests {
    @Test func repeatedBatchIsIdempotent() async throws {
        let fixture = try await TemporaryStoreFixture.make()

        let batch = try Fixtures.persistence(id: BatchID(Fixtures.uuid(301)), value: 80, ms: 100)
        _ = try await fixture.appendForTesting(batch)
        _ = try await fixture.appendForTesting(batch)

        #expect(try await fixture.rows(in: "raw_samples") == 1)
        #expect(try await fixture.rows(in: "ema_samples") == 1)
        #expect(try await fixture.rows(in: "committed_batches") == 1)
        try await fixture.closeAndDeleteSession()
    }

    @Test func sameBatchIDDifferentPayloadIsIntegrityFailure() async throws {
        let fixture = try await TemporaryStoreFixture.make()

        let batchID = BatchID(Fixtures.uuid(302))
        let first = try Fixtures.persistence(id: batchID, value: 80, ms: 100)
        let second = try Fixtures.persistence(id: batchID, value: 81, ms: 100)
        _ = try await fixture.appendForTesting(first)

        do {
            _ = try await fixture.appendForTesting(second)
            Issue.record("expected integrity failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .databaseIntegrity)
        }

        #expect(try await fixture.rows(in: "raw_samples") == 1)
        #expect(try await fixture.rows(in: "ema_samples") == 1)
        try await fixture.closeAndDeleteSession()
    }

    @Test func failedTransactionRollsBackPartialBatch() async throws {
        let fixture = try await TemporaryStoreFixture.make()

        let batch = try invalidPersistenceBatchMissingSegment()
        do {
            _ = try await fixture.appendForTesting(batch)
            Issue.record("expected foreign key failure")
        } catch is MonitorFailure {}

        #expect(try await fixture.rows(in: "raw_samples") == 0)
        #expect(try await fixture.rows(in: "ema_samples") == 0)
        #expect(try await fixture.rows(in: "committed_batches") == 0)
        try await fixture.closeAndDeleteSession()
    }

    @Test func gapEndAllowsMonotonicNullToValueUpdate() async throws {
        let fixture = try await TemporaryStoreFixture.make()

        let setup = try Fixtures.persistence(id: BatchID(Fixtures.uuid(303)), value: 70, ms: 50)
        _ = try await fixture.appendForTesting(setup)

        let openGap = try gapBatch(
            batchID: BatchID(Fixtures.uuid(304)),
            gapID: GapID(Fixtures.uuid(401)),
            endedElapsedNS: nil
        )
        _ = try await fixture.appendForTesting(openGap)

        let closedGap = try gapBatch(
            batchID: BatchID(Fixtures.uuid(305)),
            gapID: GapID(Fixtures.uuid(401)),
            endedElapsedNS: 200_000_000
        )
        _ = try await fixture.appendForTesting(closedGap)

        #expect(try await fixture.rows(in: "gaps") == 1)
        try await fixture.closeAndDeleteSession()
    }

    @Test func secondBatchReusesExistingMetadataRows() async throws {
        let fixture = try await TemporaryStoreFixture.make()

        let first = try Fixtures.persistence(id: BatchID(Fixtures.uuid(320)), value: 80, ms: 100)
        let second = try persistenceWithSampleID(
            batchID: BatchID(Fixtures.uuid(321)),
            sampleID: "fixture-session:2",
            value: 85,
            ms: 200
        )
        _ = try await fixture.appendForTesting(first)
        _ = try await fixture.appendForTesting(second)

        #expect(try await fixture.rows(in: "sources") == 1)
        #expect(try await fixture.rows(in: "series") == 1)
        #expect(try await fixture.rows(in: "raw_samples") == 2)
        #expect(try await fixture.rows(in: "ema_samples") == 2)
        #expect(try await fixture.rows(in: "committed_batches") == 2)
        try await fixture.closeAndDeleteSession()
    }

    @Test func batchStoresAggregatesTrendsAndSampleMembers() async throws {
        let fixture = try await TemporaryStoreFixture.make()

        let setup = try Fixtures.persistence(id: BatchID(Fixtures.uuid(322)), value: 80, ms: 100)
        _ = try await fixture.appendForTesting(setup)

        let enriched = try enrichedPersistenceBatch(batchID: BatchID(Fixtures.uuid(323)))
        _ = try await fixture.appendForTesting(enriched)

        #expect(try await fixture.rows(in: "aggregates") == 1)
        #expect(try await fixture.rows(in: "trend_samples") == 1)
        try await fixture.closeAndDeleteSession()
    }

    @Test func walHardLimitTriggersCapacityFailure() async throws {
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
            walSoftBytes: 16_384,
            walHardBytes: 32_768
        )
        let fixture = try await TemporaryStoreFixture.make(retentionPolicy: policy)
        for index in 0..<120 {
            let batchID = try BatchID(validating: String(format: "00000000-0000-4000-8000-%012x", 510 + index))
            _ = try await fixture.appendForTesting(try metadataBootstrap(batchID: batchID))
        }

        let walURL = URL(fileURLWithPath: fixture.databaseURL.path + "-wal")
        let walBytes = (try FileManager.default.attributesOfItem(atPath: walURL.path)[.size] as? NSNumber)?
            .int64Value ?? 0
        #expect(walBytes > policy.walHardBytes)

        do {
            try await fixture.session.prune(nowElapsedNS: 400_000_000_000)
            Issue.record("expected wal capacity failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .databaseCapacity)
            #expect(failure.underlyingCode == "capacity_exceeded")
        }
        try await fixture.closeAndDeleteSession()
    }

    @Test func gapEndRejectsConflictingClosure() async throws {
        let fixture = try await TemporaryStoreFixture.make()

        let setup = try Fixtures.persistence(id: BatchID(Fixtures.uuid(306)), value: 70, ms: 50)
        _ = try await fixture.appendForTesting(setup)

        let openGap = try gapBatch(
            batchID: BatchID(Fixtures.uuid(307)),
            gapID: GapID(Fixtures.uuid(402)),
            endedElapsedNS: nil
        )
        _ = try await fixture.appendForTesting(openGap)

        let closedGap = try gapBatch(
            batchID: BatchID(Fixtures.uuid(308)),
            gapID: GapID(Fixtures.uuid(402)),
            endedElapsedNS: 200_000_000
        )
        _ = try await fixture.appendForTesting(closedGap)

        let conflictingClose = try gapBatch(
            batchID: BatchID(Fixtures.uuid(309)),
            gapID: GapID(Fixtures.uuid(402)),
            endedElapsedNS: 300_000_000
        )
        do {
            _ = try await fixture.appendForTesting(conflictingClose)
            Issue.record("expected gap integrity failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .databaseIntegrity)
        }
        try await fixture.closeAndDeleteSession()
    }
}

private func invalidPersistenceBatchMissingSegment() throws -> PersistenceBatch {
    let timestamp = Fixtures.timestamp(ms: 100)
    return PersistenceBatch(
        batchID: BatchID(Fixtures.uuid(310)),
        sources: [Fixtures.source()],
        definitions: [try Fixtures.definition()],
        segments: [],
        raw: [
            Sample(
                sampleID: "fixture-session:missing-segment",
                seriesID: SeriesID(Fixtures.uuid(101)),
                segment: 1,
                timestamp: timestamp,
                periodMS: 200,
                valueC: 80,
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
}

private func metadataBootstrap(batchID: BatchID) throws -> PersistenceBatch {
    PersistenceBatch(
        batchID: batchID,
        sources: [Fixtures.source()],
        definitions: [try Fixtures.definition()],
        segments: [
            Segment(
                seriesID: SeriesID(Fixtures.uuid(101)),
                number: 1,
                started: Fixtures.timestamp(ms: 0),
                reason: .sessionStart
            )
        ],
        raw: [],
        ema: [],
        buckets: [],
        trends: [],
        gaps: []
    )
}

private func persistenceWithSampleID(
    batchID: BatchID,
    sampleID: String,
    value: Double,
    ms: Int64
) throws -> PersistenceBatch {
    let timestamp = Fixtures.timestamp(ms: ms)
    return PersistenceBatch(
        batchID: batchID,
        sources: [Fixtures.source()],
        definitions: [try Fixtures.definition()],
        segments: [
            Segment(
                seriesID: SeriesID(Fixtures.uuid(101)),
                number: 1,
                started: Fixtures.timestamp(ms: 0),
                reason: .sessionStart
            )
        ],
        raw: [
            Sample(
                sampleID: sampleID,
                seriesID: SeriesID(Fixtures.uuid(101)),
                segment: 1,
                timestamp: timestamp,
                periodMS: 200,
                valueC: value,
                freshness: .unknown,
                sourceWallUnixNS: nil,
                memberSampleIDs: []
            )
        ],
        ema: [
            EMAValue(
                sampleID: sampleID,
                seriesID: SeriesID(Fixtures.uuid(101)),
                segment: 1,
                timestamp: timestamp,
                valueC: value
            )
        ],
        buckets: [],
        trends: [],
        gaps: []
    )
}

private func enrichedPersistenceBatch(batchID: BatchID) throws -> PersistenceBatch {
    let timestamp = Fixtures.timestamp(ms: 200)
    return PersistenceBatch(
        batchID: batchID,
        sources: [],
        definitions: [],
        segments: [],
        raw: [
            Sample(
                sampleID: "fixture-session:derived",
                seriesID: SeriesID(Fixtures.uuid(101)),
                segment: 1,
                timestamp: timestamp,
                periodMS: 200,
                valueC: 90,
                freshness: .unknown,
                sourceWallUnixNS: nil,
                memberSampleIDs: ["fixture-session:1"]
            )
        ],
        ema: [],
        buckets: [
            Bucket(
                seriesID: SeriesID(Fixtures.uuid(101)),
                segment: 1,
                widthSeconds: 1,
                startElapsedNS: 100_000_000,
                endElapsedNS: 1_000_000_000,
                minC: 80,
                maxC: 90,
                sumC: 170,
                count: 2,
                latestC: 90,
                latestElapsedNS: 200_000_000,
                latestSampleID: "fixture-session:derived",
                isPartial: false,
                coverageNS: 900_000_000
            )
        ],
        trends: [
            TrendValue(
                seriesID: SeriesID(Fixtures.uuid(101)),
                segment: 1,
                at: timestamp,
                slopeCPerSecond: 0.5,
                direction: .rising,
                pointCount: 3
            )
        ],
        gaps: []
    )
}

private func gapBatch(
    batchID: BatchID,
    gapID: GapID,
    endedElapsedNS: Int64?
) throws -> PersistenceBatch {
    PersistenceBatch(
        batchID: batchID,
        sources: [],
        definitions: [],
        segments: [],
        raw: [],
        ema: [],
        buckets: [],
        trends: [],
        gaps: [
            Gap(
                gapID: gapID,
                seriesID: SeriesID(Fixtures.uuid(101)),
                startedElapsedNS: 100_000_000,
                endedElapsedNS: endedElapsedNS,
                reason: .readFailure
            )
        ]
    )
}
