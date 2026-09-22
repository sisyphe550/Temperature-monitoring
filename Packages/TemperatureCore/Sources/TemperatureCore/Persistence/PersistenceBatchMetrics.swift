import Foundation

enum PersistenceBatchMetrics {
    static func logicalRecordCount(_ batch: PersistenceBatch) -> Int {
        batch.sources.count
            + batch.definitions.count
            + batch.segments.count
            + batch.raw.count
            + batch.ema.count
            + batch.buckets.count
            + batch.trends.count
            + batch.gaps.count
            + batch.raw.reduce(0) { $0 + $1.memberSampleIDs.count }
            + batch.definitions.reduce(0) { $0 + $1.memberSourceIDs.count }
    }

    static func payloadBytes(_ batch: PersistenceBatch) throws -> Int {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(batch).count
    }
}
