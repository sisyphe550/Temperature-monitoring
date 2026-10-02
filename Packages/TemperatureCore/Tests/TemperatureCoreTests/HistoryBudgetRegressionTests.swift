import Foundation
import Testing
@testable import TemperatureCore

@Suite struct HistoryBudgetRegressionTests {
    @Test func sqliteBudgetAppliesAcrossSegmentsWithoutLosingPeaksOrCounts() async throws {
        let fixture = try await TemporaryStoreFixture.make()
        let seriesID = SeriesID(Fixtures.uuid(101))
        _ = try await fixture.appendForTesting(Fixtures.persistence(id: BatchID(UUID()), value: 50, ms: 0))
        let buckets = (0..<12).map { index -> Bucket in
            let start = Int64(index) * 1_000_000_000
            let value: Double = index == 3 ? 99 : (index == 8 ? 2 : 50)
            return Bucket(seriesID: seriesID, segment: index < 6 ? 1 : 2, widthSeconds: 1,
                startElapsedNS: start, endElapsedNS: start + 1_000_000_000, minC: value, maxC: value,
                sumC: value, count: 1, latestC: value, latestElapsedNS: start + 500_000_000,
                latestSampleID: "budget-\(index)", isPartial: false, coverageNS: 1_000_000_000)
        }
        _ = try await fixture.appendForTesting(PersistenceBatch(batchID: BatchID(UUID()), sources: [], definitions: [],
            segments: [Segment(seriesID: seriesID, number: 2, started: Fixtures.timestamp(ms: 6000), reason: .wake)],
            raw: [], ema: [], buckets: buckets, trends: [], gaps: []))
        let result = try await fixture.session.query(HistoryRequest(seriesIDs: [seriesID], range: .oneHour,
            asOfElapsedNS: 12_000_000_000, pointLimit: 6))
        #expect(result.points.count <= 6)
        #expect(result.points.reduce(Int64(0)) { $0 + $1.count } == 12)
        #expect(result.points.compactMap(\.maxC).max() == 99)
        #expect(result.points.compactMap(\.minC).min() == 2)
        for segment: Int64 in [1, 2] {
            let points = result.points.filter { $0.segment == segment }
            #expect(points.first?.elapsedNS == (segment == 1 ? 500_000_000 : 6_500_000_000))
            #expect(points.last?.elapsedNS == (segment == 1 ? 5_500_000_000 : 11_500_000_000))
        }
        try await fixture.closeAndDeleteSession()
    }
}
