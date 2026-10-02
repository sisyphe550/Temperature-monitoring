import CSQLite
import Foundation

enum HistoryQueryLimits {
    static let maxSeries = 8
    static let maxPointsPerSeries = 2000
    static let deadlineNS: Int64 = 250_000_000
}

struct HistoryQueryEngine {
    let store: SQLiteStore

    func execute(_ request: HistoryRequest, isCancelled: () -> Bool) throws -> HistoryResult {
        try validate(request)
        guard let layer = layer(for: request.range) else {
            throw HistoryQueryError.unsupportedRange
        }

        let windowEndNS = request.asOfElapsedNS
        let windowStartNS = windowEndNS - request.range.rawValue * 1_000_000_000
        let pointLimit = min(request.pointLimit, HistoryQueryLimits.maxPointsPerSeries)
        let viewName = viewName(for: layer)
        let started = DispatchTime.now().uptimeNanoseconds

        var points: [HistoryPoint] = []
        points.reserveCapacity(request.seriesIDs.count * pointLimit)

        let gaps = try fetchGaps(seriesIDs: request.seriesIDs,
            windowStartNS: windowStartNS, windowEndNS: windowEndNS)
        var availableFrom: Int64?
        var persistedThrough: Int64?

        for seriesID in request.seriesIDs {
            if isCancelled() {
                throw HistoryQueryError.cancelled
            }
            if DispatchTime.now().uptimeNanoseconds - started > UInt64(HistoryQueryLimits.deadlineNS) {
                throw HistoryQueryError.deadlineExceeded
            }

            let rows = try fetchBuckets(
                viewName: viewName,
                seriesID: seriesID,
                windowStartNS: windowStartNS,
                windowEndNS: windowEndNS
            )
            if let first = rows.map(\.startElapsedNS).min() {
                availableFrom = availableFrom.map { min($0, first) } ?? first
            }
            if let last = rows.map(\.endElapsedNS).max() {
                persistedThrough = persistedThrough.map { max($0, last) } ?? last
            }

            let seriesGaps = gaps.filter { $0.seriesID == seriesID }
            var runs: [[SourceBucket]] = []
            for (_, segmentRows) in Dictionary(grouping: rows, by: \.segment).sorted(by: { $0.key < $1.key }) {
                var run: [SourceBucket] = []
                for row in segmentRows {
                    if let previous = run.last, seriesGaps.contains(where: {
                        previous.latestElapsedNS < $0.startedElapsedNS && $0.startedElapsedNS <= row.latestElapsedNS
                    }) {
                        runs.append(run)
                        run = []
                    }
                    run.append(row)
                }
                if !run.isEmpty { runs.append(run) }
            }
            let mandatory = runs.map { min(2, $0.count) }
            guard mandatory.reduce(0, +) <= pointLimit else {
                throw HistoryQueryError.boundaryBudgetExceeded
            }
            let interiorCounts = runs.map { max(0, $0.count - 2) }
            let totalInterior = interiorCounts.reduce(0, +)
            let remaining = min(pointLimit - mandatory.reduce(0, +), totalInterior)
            var extra = interiorCounts.map { totalInterior == 0 ? 0 : $0 * remaining / totalInterior }
            var spare = remaining - extra.reduce(0, +)
            for index in runs.indices where spare > 0 && extra[index] < interiorCounts[index] {
                extra[index] += 1
                spare -= 1
            }
            for index in runs.indices {
                points.append(contentsOf: try downsample(runs[index], seriesID: seriesID,
                    pointLimit: mandatory[index] + extra[index], isCancelled: isCancelled, startedUptimeNS: started))
            }
        }

        return HistoryResult(
            layer: layer,
            points: points,
            gaps: gaps,
            availableFromElapsedNS: availableFrom,
            persistedThroughElapsedNS: persistedThrough
        )
    }

    private func validate(_ request: HistoryRequest) throws {
        guard !request.seriesIDs.isEmpty else {
            throw HistoryQueryError.emptySeries
        }
        guard request.seriesIDs.count <= HistoryQueryLimits.maxSeries else {
            throw HistoryQueryError.tooManySeries
        }
        guard request.pointLimit > 0,
              request.pointLimit <= HistoryQueryLimits.maxPointsPerSeries
        else {
            throw HistoryQueryError.invalidPointLimit
        }
        if Set(request.seriesIDs).count != request.seriesIDs.count {
            throw HistoryQueryError.duplicateSeries
        }
    }

    private func layer(for range: HistoryRange) -> HistoryLayer? {
        switch range {
        case .fiveMinutes:
            return nil
        case .oneHour:
            return .oneSecond
        case .oneDay:
            return .tenSeconds
        case .threeDays:
            return .oneMinute
        }
    }

    private func viewName(for layer: HistoryLayer) -> String {
        switch layer {
        case .oneSecond:
            return "samples_1s"
        case .tenSeconds:
            return "samples_10s"
        case .oneMinute:
            return "samples_1m"
        case .ema:
            return "ema_samples"
        }
    }

    private struct SourceBucket {
        let segment: Int64
        let startElapsedNS: Int64
        let endElapsedNS: Int64
        let minC: Double
        let maxC: Double
        let sumC: Double
        let count: Int64
        let latestC: Double
        let latestElapsedNS: Int64
    }

    private func fetchBuckets(
        viewName: String,
        seriesID: SeriesID,
        windowStartNS: Int64,
        windowEndNS: Int64
    ) throws -> [SourceBucket] {
        guard HistoryQueryEngine.allowedViews.contains(viewName) else {
            throw SQLiteStoreError.schemaMismatch(detail: "unsupported history view")
        }
        let sql = """
        SELECT segment, start_elapsed_ns, end_elapsed_ns, min_c, max_c, sum_c, sample_count, latest_c, latest_elapsed_ns
        FROM \(viewName)
        WHERE series_id = ?
          AND start_elapsed_ns >= ?
          AND start_elapsed_ns < ?
        ORDER BY start_elapsed_ns ASC
        """
        return try store.queryRows(sql: sql, bindings: [
            .text(seriesID.rawValue),
            .int64(windowStartNS),
            .int64(windowEndNS),
        ]) { statement in
            SourceBucket(
                segment: sqlite3_column_int64(statement, 0),
                startElapsedNS: sqlite3_column_int64(statement, 1),
                endElapsedNS: sqlite3_column_int64(statement, 2),
                minC: sqlite3_column_double(statement, 3),
                maxC: sqlite3_column_double(statement, 4),
                sumC: sqlite3_column_double(statement, 5),
                count: sqlite3_column_int64(statement, 6),
                latestC: sqlite3_column_double(statement, 7),
                latestElapsedNS: sqlite3_column_int64(statement, 8)
            )
        }
    }

    private func fetchGaps(
        seriesIDs: [SeriesID],
        windowStartNS: Int64,
        windowEndNS: Int64
    ) throws -> [Gap] {
        var gaps: [Gap] = []
        for seriesID in seriesIDs {
            let sql = """
            SELECT gap_id, start_elapsed_ns, end_elapsed_ns, reason
            FROM gaps
            WHERE series_id = ?
              AND start_elapsed_ns < ?
              AND (end_elapsed_ns IS NULL OR end_elapsed_ns > ?)
            ORDER BY start_elapsed_ns ASC
            """
            let rows = try store.queryRows(sql: sql, bindings: [
                .text(seriesID.rawValue),
                .int64(windowEndNS),
                .int64(windowStartNS),
            ]) { statement -> Gap in
                let gapID = try GapID(validating: String(cString: sqlite3_column_text(statement, 0)))
                let started = sqlite3_column_int64(statement, 1)
                let ended = sqlite3_column_type(statement, 2) == SQLITE_NULL
                    ? nil
                    : sqlite3_column_int64(statement, 2)
                let reasonRaw = String(cString: sqlite3_column_text(statement, 3))
                let reason = GapReason(rawValue: reasonRaw) ?? .readFailure
                return Gap(
                    gapID: gapID,
                    seriesID: seriesID,
                    startedElapsedNS: started,
                    endedElapsedNS: ended,
                    reason: reason
                )
            }
            gaps.append(contentsOf: rows)
        }
        return gaps
    }

    private func downsample(
        _ buckets: [SourceBucket], seriesID: SeriesID, pointLimit: Int,
        isCancelled: () -> Bool, startedUptimeNS: UInt64
    ) throws -> [HistoryPoint] {
        guard !buckets.isEmpty else { return [] }
        if isCancelled() { throw HistoryQueryError.cancelled }
        if DispatchTime.now().uptimeNanoseconds - startedUptimeNS > UInt64(HistoryQueryLimits.deadlineNS) {
            throw HistoryQueryError.deadlineExceeded
        }
        if buckets.count <= pointLimit {
            return buckets.map { merge([$0], seriesID: seriesID, elapsedNS: $0.latestElapsedNS) }
        }
        // Boundary points carry the complete envelope/count of their bin too.
        // Even a two-point budget preserves all recorded samples and both ends.
        if pointLimit == 2 {
            let midpoint = buckets.count / 2
            return [merge(Array(buckets[..<midpoint]), seriesID: seriesID, elapsedNS: buckets.first!.latestElapsedNS),
                merge(Array(buckets[midpoint...]), seriesID: seriesID, elapsedNS: buckets.last!.latestElapsedNS)]
        }
        let interior = Array(buckets.dropFirst().dropLast())
        let binCount = pointLimit - 2
        let start = interior.first!.latestElapsedNS
        let span = max(1, interior.last!.latestElapsedNS - start + 1)
        var bins = Array(repeating: [SourceBucket](), count: binCount)
        for bucket in interior {
            if isCancelled() { throw HistoryQueryError.cancelled }
            let index = min(binCount - 1, Int(Double(bucket.latestElapsedNS - start) / Double(span) * Double(binCount)))
            bins[index].append(bucket)
        }
        var output = [merge([buckets.first!], seriesID: seriesID, elapsedNS: buckets.first!.latestElapsedNS)]
        for bin in bins where !bin.isEmpty {
            if isCancelled() { throw HistoryQueryError.cancelled }
            if DispatchTime.now().uptimeNanoseconds - startedUptimeNS > UInt64(HistoryQueryLimits.deadlineNS) {
                throw HistoryQueryError.deadlineExceeded
            }
            output.append(merge(bin, seriesID: seriesID, elapsedNS: bin.last!.latestElapsedNS))
        }
        output.append(merge([buckets.last!], seriesID: seriesID, elapsedNS: buckets.last!.latestElapsedNS))
        return output
    }

    private func merge(_ buckets: [SourceBucket], seriesID: SeriesID, elapsedNS: Int64) -> HistoryPoint {
        let count = buckets.reduce(Int64(0)) { $0 + $1.count }
        let sum = buckets.reduce(0.0) { $0 + $1.sumC }
        return HistoryPoint(seriesID: seriesID, segment: buckets[0].segment, elapsedNS: elapsedNS, wallUnixNS: nil,
            valueC: count > 0 ? sum / Double(count) : buckets.last!.latestC,
            minC: buckets.map(\.minC).min(), maxC: buckets.map(\.maxC).max(), count: count)
    }

    private static let allowedViews: Set<String> = [
        "samples_1s",
        "samples_10s",
        "samples_1m",
    ]
}

enum HistoryQueryError: Error, Sendable, Equatable {
    case unsupportedRange
    case emptySeries
    case tooManySeries
    case invalidPointLimit
    case duplicateSeries
    case cancelled
    case deadlineExceeded
    case boundaryBudgetExceeded
}
