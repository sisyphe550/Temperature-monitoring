import CSQLite
import Foundation

extension SQLiteStore {
    struct CommittedBatchRecord: Equatable {
        let committedElapsedNS: Int64
        let payloadSHA256: String
    }

    func commitBatch(
        _ batch: PersistenceBatch,
        sessionID: SessionID,
        snapshotGeneration: UInt64
    ) throws -> (ProcessingReceipt, inserted: Bool) {
        let payloadHash = try BatchCanonicalHash.sha256(for: batch)
        let committedElapsedNS = maxElapsedNS(in: batch)
        let receipt = ProcessingReceipt(
            batchID: batch.batchID,
            acceptedRecords: logicalRecordCount(batch),
            snapshotGeneration: snapshotGeneration
        )

        try exec("BEGIN IMMEDIATE")
        var didCommit = false
        defer {
            if !didCommit {
                try? exec("ROLLBACK")
            }
        }

        if let existing = try fetchCommittedBatch(batch.batchID) {
            guard existing.payloadSHA256 == payloadHash else {
                throw SQLiteStoreError.integrityConflict(
                    detail: "batch \(batch.batchID.rawValue) payload mismatch"
                )
            }
            try exec("COMMIT")
            didCommit = true
            return (receipt, false)
        }

        for source in batch.sources {
            try insertOrVerifySource(source, sessionID: sessionID)
        }
        for definition in batch.definitions {
            try insertOrVerifyDefinition(definition, sessionID: sessionID)
        }
        for definition in batch.definitions {
            try insertOrVerifySeriesMembers(definition)
        }
        for segment in batch.segments {
            try insertOrVerifySegment(segment)
        }
        for sample in batch.raw {
            try insertOrVerifyRawSample(sample)
        }
        for sample in batch.raw {
            for memberID in sample.memberSampleIDs {
                try insertOrVerifySampleMember(derivedSampleID: sample.sampleID, sourceSampleID: memberID)
            }
        }
        for ema in batch.ema {
            try insertOrVerifyEMASample(ema)
        }
        for bucket in batch.buckets {
            try insertOrVerifyAggregate(bucket)
        }
        for trend in batch.trends {
            try insertOrVerifyTrend(trend)
        }
        for gap in batch.gaps {
            try insertOrUpdateGap(gap)
        }

        try bindAndRun(
            sql: """
            INSERT INTO committed_batches (batch_id, committed_elapsed_ns, payload_sha256)
            VALUES (?, ?, ?)
            """,
            bindings: [
                .text(batch.batchID.rawValue),
                .int64(committedElapsedNS),
                .text(payloadHash),
            ]
        )

        try exec("COMMIT")
        didCommit = true
        return (receipt, true)
    }

    func rowCount(in table: String) throws -> Int {
        guard Self.allowedCountTables.contains(table) else {
            throw SQLiteStoreError.schemaMismatch(detail: "unsupported table \(table)")
        }
        guard let count = try queryInt64("SELECT COUNT(*) FROM \(table)") else {
            return 0
        }
        return Int(count)
    }

    private static let allowedCountTables: Set<String> = [
        "raw_samples",
        "ema_samples",
        "committed_batches",
        "sources",
        "series",
        "segments",
        "gaps",
        "aggregates",
        "trend_samples",
        "sample_members",
    ]

    private func fetchCommittedBatch(_ batchID: BatchID) throws -> CommittedBatchRecord? {
        let sql = """
        SELECT committed_elapsed_ns, payload_sha256
        FROM committed_batches
        WHERE batch_id = ?
        LIMIT 1
        """
        return try queryRow(sql: sql, bindings: [.text(batchID.rawValue)]) { statement in
            CommittedBatchRecord(
                committedElapsedNS: sqlite3_column_int64(statement, 0),
                payloadSHA256: String(cString: sqlite3_column_text(statement, 1))
            )
        }
    }

    private func insertOrVerifySource(_ source: QualifiedSource, sessionID: SessionID) throws {
        let sql = """
        SELECT session_id, provider, raw_key, registry_id, connection_generation, kind, encoding,
               unit_evidence, mapping_version, evidence
        FROM sources
        WHERE source_id = ?
        LIMIT 1
        """
        let sourceKind = try dbSourceKind(source.kind)
        if let existing = try queryRow(sql: sql, bindings: [.text(source.sourceID.rawValue)], map: readSourceRow) {
            try verify(
                existing.sessionID == sessionID.rawValue,
                existing.provider == source.provider.rawValue,
                existing.rawKey == source.rawKey,
                existing.registryID == source.registryID,
                existing.connectionGeneration == Int64(source.connectionGeneration),
                existing.kind == sourceKind,
                existing.encoding == source.encoding,
                existing.unitEvidence == source.unitEvidence,
                existing.mappingVersion == source.mappingVersion,
                existing.evidence == source.evidence.rawValue
            )
            return
        }

        try bindAndRun(
            sql: """
            INSERT INTO sources (
                source_id, session_id, provider, raw_key, registry_id, connection_generation,
                kind, encoding, unit_evidence, mapping_version, evidence
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(source.sourceID.rawValue),
                .text(sessionID.rawValue),
                .text(source.provider.rawValue),
                .text(source.rawKey),
                .optionalText(source.registryID),
                .int64(Int64(source.connectionGeneration)),
                .text(sourceKind),
                .text(source.encoding),
                .text(source.unitEvidence),
                .text(source.mappingVersion),
                .text(source.evidence.rawValue),
            ]
        )
    }

    private struct SourceRow {
        let sessionID: String
        let provider: String
        let rawKey: String
        let registryID: String?
        let connectionGeneration: Int64
        let kind: String
        let encoding: String
        let unitEvidence: String
        let mappingVersion: String
        let evidence: String
    }

    private func readSourceRow(_ statement: OpaquePointer) -> SourceRow {
        SourceRow(
            sessionID: String(cString: sqlite3_column_text(statement, 0)),
            provider: String(cString: sqlite3_column_text(statement, 1)),
            rawKey: String(cString: sqlite3_column_text(statement, 2)),
            registryID: optionalString(statement, index: 3),
            connectionGeneration: sqlite3_column_int64(statement, 4),
            kind: String(cString: sqlite3_column_text(statement, 5)),
            encoding: String(cString: sqlite3_column_text(statement, 6)),
            unitEvidence: String(cString: sqlite3_column_text(statement, 7)),
            mappingVersion: String(cString: sqlite3_column_text(statement, 8)),
            evidence: String(cString: sqlite3_column_text(statement, 9))
        )
    }

    private func insertOrVerifyDefinition(_ definition: SeriesDefinition, sessionID: SessionID) throws {
        let sql = """
        SELECT session_id, metric_id, definition_version, kind, display_name, formula
        FROM series
        WHERE series_id = ?
        LIMIT 1
        """
        if let existing = try queryRow(sql: sql, bindings: [.text(definition.seriesID.rawValue)], map: readSeriesRow) {
            try verify(
                existing.sessionID == sessionID.rawValue,
                existing.metricID == definition.metricID.rawValue,
                existing.definitionVersion == Int64(definition.definitionVersion),
                existing.kind == definition.kind.rawValue,
                existing.displayName == definition.displayName,
                existing.formula == dbFormula(definition.formula)
            )
            return
        }

        try bindAndRun(
            sql: """
            INSERT INTO series (
                series_id, session_id, metric_id, definition_version, kind, display_name, formula
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(definition.seriesID.rawValue),
                .text(sessionID.rawValue),
                .text(definition.metricID.rawValue),
                .int64(Int64(definition.definitionVersion)),
                .text(definition.kind.rawValue),
                .text(definition.displayName),
                .text(dbFormula(definition.formula)),
            ]
        )
    }

    private struct SeriesRow {
        let sessionID: String
        let metricID: String
        let definitionVersion: Int64
        let kind: String
        let displayName: String
        let formula: String
    }

    private func readSeriesRow(_ statement: OpaquePointer) -> SeriesRow {
        SeriesRow(
            sessionID: String(cString: sqlite3_column_text(statement, 0)),
            metricID: String(cString: sqlite3_column_text(statement, 1)),
            definitionVersion: sqlite3_column_int64(statement, 2),
            kind: String(cString: sqlite3_column_text(statement, 3)),
            displayName: String(cString: sqlite3_column_text(statement, 4)),
            formula: String(cString: sqlite3_column_text(statement, 5))
        )
    }

    private func insertOrVerifySeriesMembers(_ definition: SeriesDefinition) throws {
        for (ordinal, sourceID) in definition.memberSourceIDs.enumerated() {
            let sql = """
            SELECT ordinal FROM series_members
            WHERE series_id = ? AND source_id = ?
            LIMIT 1
            """
            if let existingOrdinal = try queryRow(sql: sql, bindings: [
                .text(definition.seriesID.rawValue),
                .text(sourceID.rawValue),
            ], map: { sqlite3_column_int64($0, 0) }) {
                try verify(existingOrdinal == Int64(ordinal))
                continue
            }

            try bindAndRun(
                sql: """
                INSERT INTO series_members (series_id, source_id, ordinal)
                VALUES (?, ?, ?)
                """,
                bindings: [
                    .text(definition.seriesID.rawValue),
                    .text(sourceID.rawValue),
                    .int64(Int64(ordinal)),
                ]
            )
        }
    }

    private func insertOrVerifySegment(_ segment: Segment) throws {
        let sql = """
        SELECT start_elapsed_ns, start_wall_ns, reason
        FROM segments
        WHERE series_id = ? AND segment = ?
        LIMIT 1
        """
        if let existing = try queryRow(sql: sql, bindings: [
            .text(segment.seriesID.rawValue),
            .int64(segment.number),
        ], map: readSegmentRow) {
            try verify(
                existing.startElapsedNS == segment.started.elapsedNS,
                existing.startWallNS == segment.started.wallUnixNS,
                existing.reason == segment.reason.rawValue
            )
            return
        }

        try bindAndRun(
            sql: """
            INSERT INTO segments (series_id, segment, start_elapsed_ns, start_wall_ns, reason)
            VALUES (?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(segment.seriesID.rawValue),
                .int64(segment.number),
                .int64(segment.started.elapsedNS),
                .int64(segment.started.wallUnixNS),
                .text(segment.reason.rawValue),
            ]
        )
    }

    private struct SegmentRow {
        let startElapsedNS: Int64
        let startWallNS: Int64
        let reason: String
    }

    private func readSegmentRow(_ statement: OpaquePointer) -> SegmentRow {
        SegmentRow(
            startElapsedNS: sqlite3_column_int64(statement, 0),
            startWallNS: sqlite3_column_int64(statement, 1),
            reason: String(cString: sqlite3_column_text(statement, 2))
        )
    }

    private func insertOrVerifyRawSample(_ sample: Sample) throws {
        let sql = """
        SELECT series_id, segment, elapsed_ns, wall_ns, period_ms, value_c, freshness, source_wall_ns
        FROM raw_samples
        WHERE sample_id = ?
        LIMIT 1
        """
        if let existing = try queryRow(sql: sql, bindings: [.text(sample.sampleID)], map: readRawSampleRow) {
            try verify(
                existing.seriesID == sample.seriesID.rawValue,
                existing.segment == sample.segment,
                existing.elapsedNS == sample.timestamp.elapsedNS,
                existing.wallNS == sample.timestamp.wallUnixNS,
                existing.periodMS == Int64(sample.periodMS),
                existing.valueC == sample.valueC,
                existing.freshness == sample.freshness.rawValue,
                existing.sourceWallNS == sample.sourceWallUnixNS
            )
            return
        }

        try bindAndRun(
            sql: """
            INSERT INTO raw_samples (
                sample_id, series_id, segment, elapsed_ns, wall_ns, period_ms, value_c, freshness, source_wall_ns
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(sample.sampleID),
                .text(sample.seriesID.rawValue),
                .int64(sample.segment),
                .int64(sample.timestamp.elapsedNS),
                .int64(sample.timestamp.wallUnixNS),
                .int64(Int64(sample.periodMS)),
                .double(sample.valueC),
                .text(sample.freshness.rawValue),
                .optionalInt64(sample.sourceWallUnixNS),
            ]
        )
    }

    private struct RawSampleRow {
        let seriesID: String
        let segment: Int64
        let elapsedNS: Int64
        let wallNS: Int64
        let periodMS: Int64
        let valueC: Double
        let freshness: String
        let sourceWallNS: Int64?
    }

    private func readRawSampleRow(_ statement: OpaquePointer) -> RawSampleRow {
        RawSampleRow(
            seriesID: String(cString: sqlite3_column_text(statement, 0)),
            segment: sqlite3_column_int64(statement, 1),
            elapsedNS: sqlite3_column_int64(statement, 2),
            wallNS: sqlite3_column_int64(statement, 3),
            periodMS: sqlite3_column_int64(statement, 4),
            valueC: sqlite3_column_double(statement, 5),
            freshness: String(cString: sqlite3_column_text(statement, 6)),
            sourceWallNS: optionalInt64(statement, index: 7)
        )
    }

    private func insertOrVerifySampleMember(derivedSampleID: String, sourceSampleID: String) throws {
        let sql = """
        SELECT 1 FROM sample_members
        WHERE derived_sample_id = ? AND source_sample_id = ?
        LIMIT 1
        """
        if try queryExists(sql: sql, bindings: [.text(derivedSampleID), .text(sourceSampleID)]) {
            return
        }

        try bindAndRun(
            sql: """
            INSERT INTO sample_members (derived_sample_id, source_sample_id)
            VALUES (?, ?)
            """,
            bindings: [.text(derivedSampleID), .text(sourceSampleID)]
        )
    }

    private func insertOrVerifyEMASample(_ ema: EMAValue) throws {
        let sql = """
        SELECT series_id, segment, elapsed_ns, wall_ns, value_c
        FROM ema_samples
        WHERE sample_id = ?
        LIMIT 1
        """
        if let existing = try queryRow(sql: sql, bindings: [.text(ema.sampleID)], map: readEMARow) {
            try verify(
                existing.seriesID == ema.seriesID.rawValue,
                existing.segment == ema.segment,
                existing.elapsedNS == ema.timestamp.elapsedNS,
                existing.wallNS == ema.timestamp.wallUnixNS,
                existing.valueC == ema.valueC
            )
            return
        }

        try bindAndRun(
            sql: """
            INSERT INTO ema_samples (sample_id, series_id, segment, elapsed_ns, wall_ns, value_c)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(ema.sampleID),
                .text(ema.seriesID.rawValue),
                .int64(ema.segment),
                .int64(ema.timestamp.elapsedNS),
                .int64(ema.timestamp.wallUnixNS),
                .double(ema.valueC),
            ]
        )
    }

    private struct EMARow {
        let seriesID: String
        let segment: Int64
        let elapsedNS: Int64
        let wallNS: Int64
        let valueC: Double
    }

    private func readEMARow(_ statement: OpaquePointer) -> EMARow {
        EMARow(
            seriesID: String(cString: sqlite3_column_text(statement, 0)),
            segment: sqlite3_column_int64(statement, 1),
            elapsedNS: sqlite3_column_int64(statement, 2),
            wallNS: sqlite3_column_int64(statement, 3),
            valueC: sqlite3_column_double(statement, 4)
        )
    }

    private func insertOrVerifyAggregate(_ bucket: Bucket) throws {
        let sql = """
        SELECT series_id, segment, width_s, start_elapsed_ns, end_elapsed_ns, min_c, max_c, sum_c,
               latest_c, latest_elapsed_ns, latest_sample_id, sample_count, coverage_ns, partial
        FROM aggregates
        WHERE series_id = ? AND segment = ? AND width_s = ? AND start_elapsed_ns = ?
        LIMIT 1
        """
        if let existing = try queryRow(sql: sql, bindings: [
            .text(bucket.seriesID.rawValue),
            .int64(bucket.segment),
            .int64(Int64(bucket.widthSeconds)),
            .int64(bucket.startElapsedNS),
        ], map: readAggregateRow) {
            try verify(
                existing.endElapsedNS == bucket.endElapsedNS,
                existing.minC == bucket.minC,
                existing.maxC == bucket.maxC,
                existing.sumC == bucket.sumC,
                existing.latestC == bucket.latestC,
                existing.latestElapsedNS == bucket.latestElapsedNS,
                existing.latestSampleID == bucket.latestSampleID,
                existing.sampleCount == bucket.count,
                existing.coverageNS == bucket.coverageNS,
                existing.partial == (bucket.isPartial ? 1 : 0)
            )
            return
        }

        try bindAndRun(
            sql: """
            INSERT INTO aggregates (
                series_id, segment, width_s, start_elapsed_ns, end_elapsed_ns, min_c, max_c, sum_c,
                latest_c, latest_elapsed_ns, latest_sample_id, sample_count, coverage_ns, partial
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(bucket.seriesID.rawValue),
                .int64(bucket.segment),
                .int64(Int64(bucket.widthSeconds)),
                .int64(bucket.startElapsedNS),
                .int64(bucket.endElapsedNS),
                .double(bucket.minC),
                .double(bucket.maxC),
                .double(bucket.sumC),
                .double(bucket.latestC),
                .int64(bucket.latestElapsedNS),
                .text(bucket.latestSampleID),
                .int64(bucket.count),
                .int64(bucket.coverageNS),
                .int64(bucket.isPartial ? 1 : 0),
            ]
        )
    }

    private struct AggregateRow {
        let endElapsedNS: Int64
        let minC: Double
        let maxC: Double
        let sumC: Double
        let latestC: Double
        let latestElapsedNS: Int64
        let latestSampleID: String
        let sampleCount: Int64
        let coverageNS: Int64
        let partial: Int64
    }

    private func readAggregateRow(_ statement: OpaquePointer) -> AggregateRow {
        AggregateRow(
            endElapsedNS: sqlite3_column_int64(statement, 4),
            minC: sqlite3_column_double(statement, 5),
            maxC: sqlite3_column_double(statement, 6),
            sumC: sqlite3_column_double(statement, 7),
            latestC: sqlite3_column_double(statement, 8),
            latestElapsedNS: sqlite3_column_int64(statement, 9),
            latestSampleID: String(cString: sqlite3_column_text(statement, 10)),
            sampleCount: sqlite3_column_int64(statement, 11),
            coverageNS: sqlite3_column_int64(statement, 12),
            partial: sqlite3_column_int64(statement, 13)
        )
    }

    private func insertOrVerifyTrend(_ trend: TrendValue) throws {
        let sql = """
        SELECT elapsed_ns, wall_ns, slope_c_per_s, direction, point_count
        FROM trend_samples
        WHERE series_id = ? AND segment = ? AND elapsed_ns = ?
        LIMIT 1
        """
        if let existing = try queryRow(sql: sql, bindings: [
            .text(trend.seriesID.rawValue),
            .int64(trend.segment),
            .int64(trend.at.elapsedNS),
        ], map: readTrendRow) {
            try verify(
                existing.wallNS == trend.at.wallUnixNS,
                existing.slopeCPerSecond == trend.slopeCPerSecond,
                existing.direction == trend.direction.rawValue,
                existing.pointCount == Int64(trend.pointCount)
            )
            return
        }

        try bindAndRun(
            sql: """
            INSERT INTO trend_samples (
                series_id, segment, elapsed_ns, wall_ns, slope_c_per_s, direction, point_count
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(trend.seriesID.rawValue),
                .int64(trend.segment),
                .int64(trend.at.elapsedNS),
                .int64(trend.at.wallUnixNS),
                .optionalDouble(trend.slopeCPerSecond),
                .text(trend.direction.rawValue),
                .int64(Int64(trend.pointCount)),
            ]
        )
    }

    private struct TrendRow {
        let wallNS: Int64
        let slopeCPerSecond: Double?
        let direction: String
        let pointCount: Int64
    }

    private func readTrendRow(_ statement: OpaquePointer) -> TrendRow {
        TrendRow(
            wallNS: sqlite3_column_int64(statement, 1),
            slopeCPerSecond: optionalDouble(statement, index: 2),
            direction: String(cString: sqlite3_column_text(statement, 3)),
            pointCount: sqlite3_column_int64(statement, 4)
        )
    }

    private func insertOrUpdateGap(_ gap: Gap) throws {
        let sql = """
        SELECT series_id, start_elapsed_ns, end_elapsed_ns, reason
        FROM gaps
        WHERE gap_id = ?
        LIMIT 1
        """
        if let existing = try queryRow(sql: sql, bindings: [.text(gap.gapID.rawValue)], map: readGapRow) {
            if existing.seriesID == gap.seriesID.rawValue,
               existing.startElapsedNS == gap.startedElapsedNS,
               existing.reason == gap.reason.rawValue,
               existing.endElapsedNS == gap.endedElapsedNS
            {
                return
            }
            if existing.endElapsedNS == nil, let ended = gap.endedElapsedNS {
                try verify(
                    existing.seriesID == gap.seriesID.rawValue,
                    existing.startElapsedNS == gap.startedElapsedNS,
                    existing.reason == gap.reason.rawValue,
                    ended >= existing.startElapsedNS
                )
                try bindAndRun(
                    sql: """
                    UPDATE gaps SET end_elapsed_ns = ?
                    WHERE gap_id = ?
                    """,
                    bindings: [.int64(ended), .text(gap.gapID.rawValue)]
                )
                return
            }
            throw SQLiteStoreError.integrityConflict(detail: "gap \(gap.gapID.rawValue) conflict")
        }

        try bindAndRun(
            sql: """
            INSERT INTO gaps (gap_id, series_id, start_elapsed_ns, end_elapsed_ns, reason)
            VALUES (?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(gap.gapID.rawValue),
                .text(gap.seriesID.rawValue),
                .int64(gap.startedElapsedNS),
                .optionalInt64(gap.endedElapsedNS),
                .text(gap.reason.rawValue),
            ]
        )
    }

    private struct GapRow {
        let seriesID: String
        let startElapsedNS: Int64
        let endElapsedNS: Int64?
        let reason: String
    }

    private func readGapRow(_ statement: OpaquePointer) -> GapRow {
        GapRow(
            seriesID: String(cString: sqlite3_column_text(statement, 0)),
            startElapsedNS: sqlite3_column_int64(statement, 1),
            endElapsedNS: optionalInt64(statement, index: 2),
            reason: String(cString: sqlite3_column_text(statement, 3))
        )
    }

    private func maxElapsedNS(in batch: PersistenceBatch) -> Int64 {
        var maxValue: Int64 = 0
        for sample in batch.raw {
            maxValue = max(maxValue, sample.timestamp.elapsedNS)
        }
        for ema in batch.ema {
            maxValue = max(maxValue, ema.timestamp.elapsedNS)
        }
        for bucket in batch.buckets {
            maxValue = max(maxValue, bucket.endElapsedNS)
        }
        for trend in batch.trends {
            maxValue = max(maxValue, trend.at.elapsedNS)
        }
        for gap in batch.gaps {
            maxValue = max(maxValue, gap.startedElapsedNS)
            if let ended = gap.endedElapsedNS {
                maxValue = max(maxValue, ended)
            }
        }
        for segment in batch.segments {
            maxValue = max(maxValue, segment.started.elapsedNS)
        }
        return maxValue
    }

    func logicalRecordCount(_ batch: PersistenceBatch) -> Int {
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

    private func dbSourceKind(_ kind: SensorKind) throws -> String {
        switch kind {
        case .cpuMain:
            throw SQLiteStoreError.integrityConflict(detail: "cpuMain is not storable in sources")
        case .cpuZone, .ssd, .battery:
            return kind.rawValue
        }
    }

    private func dbFormula(_ formula: SeriesFormula) -> String {
        switch formula {
        case .identity: "identity"
        case .maximum: "max"
        }
    }

    private func verify(_ conditions: Bool...) throws {
        guard conditions.allSatisfy({ $0 }) else {
            throw SQLiteStoreError.integrityConflict(detail: "existing row mismatch")
        }
    }

    private func optionalString(_ statement: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index)
        else {
            return nil
        }
        return String(cString: text)
    }

    private func optionalInt64(_ statement: OpaquePointer, index: Int32) -> Int64? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return sqlite3_column_int64(statement, index)
    }

    private func optionalDouble(_ statement: OpaquePointer, index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return sqlite3_column_double(statement, index)
    }
}
