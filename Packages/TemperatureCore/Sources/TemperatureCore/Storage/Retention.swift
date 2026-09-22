import CSQLite
import Foundation

struct RetentionPolicy: Sendable, Equatable {
    let retention: RetentionSeconds
    let graceSeconds: Int64
    let dbSoftBytes: Int64
    let dbHardBytes: Int64
    let walSoftBytes: Int64
    let walHardBytes: Int64
    let committedBatchRetentionSeconds: Int64

    init(configuration: RuntimeConfiguration) {
        retention = configuration.retentionSeconds
        graceSeconds = configuration.retentionGraceSeconds
        dbSoftBytes = configuration.dbSoftBytes
        dbHardBytes = configuration.dbHardBytes
        walSoftBytes = configuration.walSoftBytes
        walHardBytes = configuration.walHardBytes
        committedBatchRetentionSeconds = 600
    }

    init(
        retention: RetentionSeconds,
        graceSeconds: Int64,
        dbSoftBytes: Int64,
        dbHardBytes: Int64,
        walSoftBytes: Int64,
        walHardBytes: Int64,
        committedBatchRetentionSeconds: Int64 = 600
    ) {
        self.retention = retention
        self.graceSeconds = graceSeconds
        self.dbSoftBytes = dbSoftBytes
        self.dbHardBytes = dbHardBytes
        self.walSoftBytes = walSoftBytes
        self.walHardBytes = walHardBytes
        self.committedBatchRetentionSeconds = committedBatchRetentionSeconds
    }
}

struct StorageCapacity: Sendable, Equatable {
    let effectiveDatabaseBytes: Int64
    let databaseFileBytes: Int64
    let walFileBytes: Int64
}

enum RetentionError: Error, Sendable, Equatable {
    case cleanupGraceExceeded
    case capacityExceeded
    case walCapacityExceeded
}

struct RetentionEngine {
    let store: SQLiteStore
    let policy: RetentionPolicy

    func prune(nowElapsedNS: Int64) throws {
        try execRetentionTransaction(nowElapsedNS: nowElapsedNS)
        try verifyCleanupGrace(nowElapsedNS: nowElapsedNS)
        try store.walCheckpointPassive()
        try enforceCapacityLimits()
    }

    private func verifyCleanupGrace(nowElapsedNS: Int64) throws {
        if try store.hasRawSamples(beforeOrAt: graceCutoff(nowElapsedNS, retentionSeconds: policy.retention.raw)) {
            throw RetentionError.cleanupGraceExceeded
        }
        if try store.hasEMASamples(beforeOrAt: graceCutoff(nowElapsedNS, retentionSeconds: policy.retention.ema)) {
            throw RetentionError.cleanupGraceExceeded
        }
        if try store.hasAggregates(
            widthSeconds: 1,
            endBeforeOrAt: graceCutoff(nowElapsedNS, retentionSeconds: policy.retention.oneSecond)
        ) {
            throw RetentionError.cleanupGraceExceeded
        }
        if try store.hasAggregates(
            widthSeconds: 10,
            endBeforeOrAt: graceCutoff(nowElapsedNS, retentionSeconds: policy.retention.tenSeconds)
        ) {
            throw RetentionError.cleanupGraceExceeded
        }
        if try store.hasAggregates(
            widthSeconds: 60,
            endBeforeOrAt: graceCutoff(nowElapsedNS, retentionSeconds: policy.retention.oneMinute)
        ) {
            throw RetentionError.cleanupGraceExceeded
        }
    }

    private func execRetentionTransaction(nowElapsedNS: Int64) throws {
        try store.exec("BEGIN IMMEDIATE")
        var committed = false
        defer {
            if !committed {
                try? store.exec("ROLLBACK")
            }
        }

        try store.deleteRawSamples(
            beforeOrAt: cutoff(nowElapsedNS, retentionSeconds: policy.retention.raw)
        )
        try store.deleteEMASamples(
            beforeOrAt: cutoff(nowElapsedNS, retentionSeconds: policy.retention.ema)
        )
        try store.deleteTrendSamples(
            beforeOrAt: cutoff(nowElapsedNS, retentionSeconds: policy.retention.trend)
        )
        try store.deleteAggregates(
            widthSeconds: 1,
            endBeforeOrAt: cutoff(nowElapsedNS, retentionSeconds: policy.retention.oneSecond)
        )
        try store.deleteAggregates(
            widthSeconds: 10,
            endBeforeOrAt: cutoff(nowElapsedNS, retentionSeconds: policy.retention.tenSeconds)
        )
        try store.deleteAggregates(
            widthSeconds: 60,
            endBeforeOrAt: cutoff(nowElapsedNS, retentionSeconds: policy.retention.oneMinute)
        )
        try store.deleteClosedGaps(
            endBeforeOrAt: cutoff(nowElapsedNS, retentionSeconds: policy.retention.oneMinute)
        )
        try store.deleteCommittedBatches(
            beforeOrAt: cutoff(nowElapsedNS, retentionSeconds: policy.committedBatchRetentionSeconds)
        )

        try store.exec("COMMIT")
        committed = true
    }

    private func enforceCapacityLimits() throws {
        let capacity = try store.storageCapacity()
        if capacity.databaseFileBytes > policy.dbHardBytes {
            throw RetentionError.capacityExceeded
        }
        if capacity.walFileBytes > policy.walHardBytes {
            throw RetentionError.walCapacityExceeded
        }
        _ = capacity.effectiveDatabaseBytes > policy.dbSoftBytes
        _ = capacity.walFileBytes > policy.walSoftBytes
    }

    private func cutoff(_ nowElapsedNS: Int64, retentionSeconds: Int64) -> Int64 {
        nowElapsedNS - retentionSeconds * 1_000_000_000
    }

    private func graceCutoff(_ nowElapsedNS: Int64, retentionSeconds: Int64) -> Int64 {
        nowElapsedNS - (retentionSeconds + policy.graceSeconds) * 1_000_000_000
    }
}

extension SQLiteStore {
    func walCheckpointPassive() throws {
        try exec("PRAGMA wal_checkpoint(PASSIVE)")
    }

    func storageCapacity() throws -> StorageCapacity {
        let pageSize = try queryInt64("PRAGMA page_size") ?? 4096
        let pageCount = try queryInt64("PRAGMA page_count") ?? 0
        let freelistCount = try queryInt64("PRAGMA freelist_count") ?? 0
        let effectivePages = max(0, pageCount - freelistCount)
        let databaseFileBytes = Int64(
            (try FileManager.default.attributesOfItem(atPath: databaseURL.path)[.size] as? NSNumber)?
                .int64Value ?? 0
        )
        let walURL = URL(fileURLWithPath: databaseURL.path + "-wal")
        let walFileBytes: Int64
        if FileManager.default.fileExists(atPath: walURL.path) {
            walFileBytes = Int64(
                (try FileManager.default.attributesOfItem(atPath: walURL.path)[.size] as? NSNumber)?
                    .int64Value ?? 0
            )
        } else {
            walFileBytes = 0
        }
        return StorageCapacity(
            effectiveDatabaseBytes: effectivePages * pageSize,
            databaseFileBytes: databaseFileBytes,
            walFileBytes: walFileBytes
        )
    }

    func hasRawSamples(beforeOrAt elapsedNS: Int64) throws -> Bool {
        try queryExists(
            sql: "SELECT 1 FROM raw_samples WHERE elapsed_ns <= ? LIMIT 1",
            bindings: [.int64(elapsedNS)]
        )
    }

    func hasEMASamples(beforeOrAt elapsedNS: Int64) throws -> Bool {
        try queryExists(
            sql: "SELECT 1 FROM ema_samples WHERE elapsed_ns <= ? LIMIT 1",
            bindings: [.int64(elapsedNS)]
        )
    }

    func hasAggregates(widthSeconds: Int, endBeforeOrAt elapsedNS: Int64) throws -> Bool {
        try queryExists(
            sql: """
            SELECT 1 FROM aggregates
            WHERE width_s = ? AND end_elapsed_ns <= ?
            LIMIT 1
            """,
            bindings: [.int64(Int64(widthSeconds)), .int64(elapsedNS)]
        )
    }

    func deleteRawSamples(beforeOrAt elapsedNS: Int64) throws {
        try bindAndRun(
            sql: """
            DELETE FROM raw_samples
            WHERE elapsed_ns <= ?
              AND EXISTS (
                SELECT 1 FROM aggregates
                WHERE width_s = 1
                  AND series_id = raw_samples.series_id
                  AND segment = raw_samples.segment
                  AND start_elapsed_ns <= raw_samples.elapsed_ns
                  AND end_elapsed_ns > raw_samples.elapsed_ns
              )
            """,
            bindings: [.int64(elapsedNS)]
        )
    }

    func deleteEMASamples(beforeOrAt elapsedNS: Int64) throws {
        try bindAndRun(
            sql: """
            DELETE FROM ema_samples
            WHERE elapsed_ns <= ?
              AND EXISTS (
                SELECT 1 FROM aggregates
                WHERE width_s = 1
                  AND series_id = ema_samples.series_id
                  AND segment = ema_samples.segment
                  AND start_elapsed_ns <= ema_samples.elapsed_ns
                  AND end_elapsed_ns > ema_samples.elapsed_ns
              )
            """,
            bindings: [.int64(elapsedNS)]
        )
    }

    func deleteTrendSamples(beforeOrAt elapsedNS: Int64) throws {
        try bindAndRun(
            sql: "DELETE FROM trend_samples WHERE elapsed_ns <= ?",
            bindings: [.int64(elapsedNS)]
        )
    }

    func deleteAggregates(widthSeconds: Int, endBeforeOrAt elapsedNS: Int64) throws {
        try bindAndRun(
            sql: """
            DELETE FROM aggregates
            WHERE width_s = ? AND end_elapsed_ns <= ?
            """,
            bindings: [.int64(Int64(widthSeconds)), .int64(elapsedNS)]
        )
    }

    func deleteClosedGaps(endBeforeOrAt elapsedNS: Int64) throws {
        try bindAndRun(
            sql: """
            DELETE FROM gaps
            WHERE end_elapsed_ns IS NOT NULL AND end_elapsed_ns <= ?
            """,
            bindings: [.int64(elapsedNS)]
        )
    }

    func deleteCommittedBatches(beforeOrAt elapsedNS: Int64) throws {
        try bindAndRun(
            sql: "DELETE FROM committed_batches WHERE committed_elapsed_ns <= ?",
            bindings: [.int64(elapsedNS)]
        )
    }

    func minRawElapsedNS() throws -> Int64? {
        try queryInt64("SELECT MIN(elapsed_ns) FROM raw_samples")
    }

    func minAggregateEndElapsedNS(widthSeconds: Int) throws -> Int64? {
        try queryRow(
            sql: "SELECT MIN(end_elapsed_ns) FROM aggregates WHERE width_s = ?",
            bindings: [.int64(Int64(widthSeconds))]
        ) { sqlite3_column_int64($0, 0) }
    }
}
