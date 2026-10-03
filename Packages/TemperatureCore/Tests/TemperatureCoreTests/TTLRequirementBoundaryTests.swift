import CSQLite
import Foundation
import Testing
@testable import TemperatureCore

// Storage/component tests with virtual elapsed time; these are not a 72 h hardware run.
@Suite struct TTLRequirementBoundaryTests {
    @Test func onePruneAppliesEveryLayerCutoffAndPreservesRawWithoutCommittedParents() async throws {
        let fixture = try await TemporaryStoreFixture.make()
        do {
            let now = ttlSeconds(300_000)
            let rawCutoff = now - ttlSeconds(300)
            let seriesID = SeriesID(Fixtures.uuid(101))
            let orphanSeriesID = SeriesID(Fixtures.uuid(102))
            let raw = [-1, 0, 1].map { delta in
                ttlSample(id: "raw-\(delta)", seriesID: seriesID,
                    elapsed: rawCutoff + Int64(delta), value: Double(51 + delta))
            } + [ttlSample(id: "parentless", seriesID: orphanSeriesID,
                elapsed: rawCutoff - 1, value: 64)]
            let ema = raw.map { EMAValue(sampleID: $0.sampleID, seriesID: $0.seriesID,
                segment: $0.segment, timestamp: $0.timestamp, valueC: $0.valueC) }
            let rawParents = [
                ttlParent(samples: [raw[0]], start: rawCutoff - ttlSeconds(1)),
                ttlParent(samples: Array(raw[1...2]), start: rawCutoff)
            ]
            // The vectors come from the documented TTLs, independent of RetentionPolicy.
            // Distinct primary keys make deletion of the wrong boundary observable.
            let boundaries: [(width: Int, ttl: Int64)] = [(1, 3600), (10, 86400), (60, 259200)]
            let boundaryBuckets = boundaries.flatMap { boundary in
                [-1, 0, 1].map { delta in
                    ttlBucket(id: "width-\(boundary.width)-\(delta)", seriesID: seriesID,
                        width: boundary.width, end: now - ttlSeconds(boundary.ttl) + Int64(delta),
                        value: Double(51 + delta))
                }
            }
            // Lower layers have committed parents before their TTL deletion.
            let parents = rawParents + [
                ttlAggregateParent(children: boundaryBuckets.filter { $0.widthSeconds == 1 },
                    width: 10, start: now - ttlSeconds(3600) - ttlSeconds(5)),
                ttlAggregateParent(children: boundaryBuckets.filter { $0.widthSeconds == 10 },
                    width: 60, start: now - ttlSeconds(86400) - ttlSeconds(30))
            ]
            let trendCutoff = now - ttlSeconds(3600)
            let trends = [-1, 0, 1].map { delta in
                TrendValue(seriesID: seriesID, segment: 1,
                    at: ttlTimestamp(trendCutoff + Int64(delta)), slopeCPerSecond: 0,
                    direction: .stable, pointCount: 5)
            }
            _ = try await fixture.appendForTesting(ttlBatch(raw: raw, ema: ema,
                buckets: parents + boundaryBuckets, trends: trends))
            let rawSQL = "SELECT sample_id FROM raw_samples"
            let emaSQL = "SELECT sample_id FROM ema_samples"
            let bucketSQL = "SELECT CAST(width_s AS TEXT) || '|' || latest_sample_id FROM aggregates"
            let trendSQL = "SELECT CAST(elapsed_ns AS TEXT) FROM trend_samples"
            #expect(try ttlStoredKeys(fixture.databaseURL, sql: rawSQL) == Set(raw.map(\.sampleID)))
            #expect(try ttlStoredKeys(fixture.databaseURL, sql: emaSQL) == Set(raw.map(\.sampleID)))
            #expect(try ttlStoredKeys(fixture.databaseURL, sql: bucketSQL)
                == Set((parents + boundaryBuckets).map(ttlBucketKey)))
            #expect(try ttlStoredKeys(fixture.databaseURL, sql: trendSQL)
                == Set(trends.map { String($0.at.elapsedNS) }))

            // One production transaction must clear all six TTL layers.
            try await fixture.session.prune(nowElapsedNS: now)

            #expect(try ttlStoredKeys(fixture.databaseURL, sql: rawSQL) == Set(["raw-1", "parentless"]))
            #expect(try ttlStoredKeys(fixture.databaseURL, sql: emaSQL) == Set(["raw-1", "parentless"]))
            #expect(try ttlStoredKeys(fixture.databaseURL, sql: bucketSQL)
                == Set(parents.map(ttlBucketKey) + boundaries.map { "\($0.width)|width-\($0.width)-1" }))
            #expect(try ttlStoredKeys(fixture.databaseURL, sql: trendSQL) == Set([String(trendCutoff + 1)]))
        } catch {
            try? await fixture.closeAndDeleteSession()
            throw error
        }
        try await fixture.closeAndDeleteSession()
    }

    @Test func threeDayQueryFiltersExpiredRowsBeforePhysicalPrune() async throws {
        let fixture = try await TemporaryStoreFixture.make()
        do {
            let now = ttlSeconds(300_000)
            let cutoff = now - ttlSeconds(259_200)
            let seriesID = SeriesID(Fixtures.uuid(101))
            let expired = [
                ttlBucket(id: "expired-before", seriesID: seriesID, width: 60, end: cutoff - 1, value: 93),
                ttlBucket(id: "expired-at", seriesID: seriesID, width: 60, end: cutoff, value: 92)
            ]
            let valid = ttlBucket(id: "valid-inside", seriesID: seriesID, width: 60,
                end: cutoff + ttlSeconds(60), value: 51)
            _ = try await fixture.appendForTesting(ttlBatch(buckets: expired + [valid]))
            let sql = "SELECT latest_sample_id FROM aggregates"
            let allIDs = Set((expired + [valid]).map(\.latestSampleID))
            #expect(try ttlStoredKeys(fixture.databaseURL, sql: sql) == allIDs)

            // Deliberately do not call prune: this tests the query's freshness boundary.
            let result = try await fixture.session.query(HistoryRequest(seriesIDs: [seriesID],
                range: .threeDays, asOfElapsedNS: now, pointLimit: 100))
            #expect(result.layer == .oneMinute)
            #expect(result.points.map(\.elapsedNS) == [valid.latestElapsedNS])
            #expect(result.points.map(\.valueC) == [51])
            #expect(result.availableFromElapsedNS == valid.startElapsedNS)
            #expect(result.persistedThroughElapsedNS == valid.endElapsedNS)
            #expect(try ttlStoredKeys(fixture.databaseURL, sql: sql) == allIDs)
        } catch {
            try? await fixture.closeAndDeleteSession()
            throw error
        }
        try await fixture.closeAndDeleteSession()
    }
}

private func ttlSeconds(_ value: Int64) -> Int64 { value * 1_000_000_000 }

private func ttlTimestamp(_ elapsed: Int64) -> Timestamp {
    Timestamp(elapsedNS: elapsed, wallUnixNS: 1_700_000_000_000_000_000 + elapsed)
}

private func ttlSample(id: String, seriesID: SeriesID, elapsed: Int64, value: Double) -> Sample {
    Sample(sampleID: id, seriesID: seriesID, segment: 1, timestamp: ttlTimestamp(elapsed),
        periodMS: 200, valueC: value, freshness: .unknown, sourceWallUnixNS: nil, memberSampleIDs: [])
}

private func ttlBucket(id: String, seriesID: SeriesID, width: Int, end: Int64, value: Double) -> Bucket {
    Bucket(seriesID: seriesID, segment: 1, widthSeconds: width,
        startElapsedNS: end - ttlSeconds(Int64(width)), endElapsedNS: end,
        minC: value, maxC: value, sumC: value, count: 1, latestC: value,
        latestElapsedNS: end - 1, latestSampleID: id, isPartial: true, coverageNS: 1)
}

private func ttlParent(samples: [Sample], start: Int64) -> Bucket {
    let latest = samples.last!
    return Bucket(seriesID: latest.seriesID, segment: latest.segment, widthSeconds: 1,
        startElapsedNS: start, endElapsedNS: start + ttlSeconds(1),
        minC: samples.map(\.valueC).min()!, maxC: samples.map(\.valueC).max()!,
        sumC: samples.reduce(0) { $0 + $1.valueC }, count: Int64(samples.count),
        latestC: latest.valueC, latestElapsedNS: latest.timestamp.elapsedNS,
        latestSampleID: latest.sampleID, isPartial: true,
        coverageNS: min(ttlSeconds(1), latest.timestamp.elapsedNS - samples[0].timestamp.elapsedNS + 200_000_000))
}

private func ttlAggregateParent(children: [Bucket], width: Int, start: Int64) -> Bucket {
    let latest = children.last!
    return Bucket(seriesID: latest.seriesID, segment: latest.segment, widthSeconds: width,
        startElapsedNS: start, endElapsedNS: start + ttlSeconds(Int64(width)),
        minC: children.map(\.minC).min()!, maxC: children.map(\.maxC).max()!,
        sumC: children.reduce(0) { $0 + $1.sumC }, count: children.reduce(0) { $0 + $1.count },
        latestC: latest.latestC, latestElapsedNS: latest.latestElapsedNS,
        latestSampleID: latest.latestSampleID, isPartial: true,
        coverageNS: children.reduce(0) { $0 + $1.coverageNS })
}

private func ttlBucketKey(_ bucket: Bucket) -> String {
    "\(bucket.widthSeconds)|\(bucket.latestSampleID)"
}

private func ttlBatch(raw: [Sample] = [], ema: [EMAValue] = [], buckets: [Bucket] = [],
    trends: [TrendValue] = []) throws -> PersistenceBatch {
    let definition = try Fixtures.definition()
    let orphanDefinition = SeriesDefinition(seriesID: SeriesID(Fixtures.uuid(102)),
        metricID: try MetricID(validating: "fixture.parentless"), definitionVersion: 1,
        kind: .cpuZone, displayName: "无父桶测试来源", memberSourceIDs: definition.memberSourceIDs, formula: .identity)
    return PersistenceBatch(batchID: BatchID(UUID()), sources: [Fixtures.source()],
        definitions: [definition, orphanDefinition],
        segments: [definition, orphanDefinition].map { Segment(seriesID: $0.seriesID,
            number: 1, started: ttlTimestamp(0), reason: .sessionStart) },
        raw: raw, ema: ema, buckets: buckets, trends: trends, gaps: [])
}

private func ttlStoredKeys(_ url: URL, sql: String) throws -> Set<String> {
    let store = try SQLiteStore(databaseURL: url)
    defer { store.close() }
    return Set(try store.queryRows(sql: sql, bindings: []) { statement in
        String(cString: sqlite3_column_text(statement, 0)!)
    })
}
