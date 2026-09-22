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

            let grouped = Dictionary(grouping: rows, by: \.segment)
            for (segment, segmentRows) in grouped.sorted(by: { $0.key < $1.key }) {
                let binned = try downsample(
                    segmentRows,
                    seriesID: seriesID,
                    segment: segment,
                    windowStartNS: windowStartNS,
                    windowEndNS: windowEndNS,
                    pointLimit: pointLimit,
                    isCancelled: isCancelled,
                    startedUptimeNS: started
                )
                points.append(contentsOf: binned)
            }
        }

        let gaps = try fetchGaps(
            seriesIDs: request.seriesIDs,
            windowStartNS: windowStartNS,
            windowEndNS: windowEndNS
        )

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
        _ buckets: [SourceBucket],
        seriesID: SeriesID,
        segment: Int64,
        windowStartNS: Int64,
        windowEndNS: Int64,
        pointLimit: Int,
        isCancelled: () -> Bool,
        startedUptimeNS: UInt64
    ) throws -> [HistoryPoint] {
        guard !buckets.isEmpty else { return [] }
        if buckets.count <= pointLimit {
            return buckets.map {
                HistoryPoint(
                    seriesID: seriesID,
                    segment: segment,
                    elapsedNS: $0.latestElapsedNS,
                    wallUnixNS: nil,
                    valueC: $0.count > 0 ? $0.sumC / Double($0.count) : $0.latestC,
                    minC: $0.minC,
                    maxC: $0.maxC,
                    count: $0.count
                )
            }
        }

        let span = max(windowEndNS - windowStartNS, 1)
        let binWidth = max(1, span / Int64(pointLimit))
        var grouped = Array(repeating: [SourceBucket](), count: pointLimit)

        for bucket in buckets {
            if isCancelled() {
                return []
            }
            let rawIndex = Int((bucket.startElapsedNS - windowStartNS) / binWidth)
            let binIndex = min(max(rawIndex, 0), pointLimit - 1)
            grouped[binIndex].append(bucket)
        }

        var output: [HistoryPoint] = []
        output.reserveCapacity(pointLimit)
        for (index, overlapping) in grouped.enumerated() where !overlapping.isEmpty {
            if isCancelled() {
                return output
            }
            if DispatchTime.now().uptimeNanoseconds - startedUptimeNS > UInt64(HistoryQueryLimits.deadlineNS) {
                throw HistoryQueryError.deadlineExceeded
            }

            let binStart = windowStartNS + Int64(index) * binWidth
            let binEnd = index == pointLimit - 1 ? windowEndNS : windowStartNS + Int64(index + 1) * binWidth
            let inBin = overlapping.filter { $0.startElapsedNS < binEnd && $0.endElapsedNS > binStart }
            guard !inBin.isEmpty else { continue }

            let minC = inBin.map(\.minC).min() ?? inBin[0].minC
            let maxC = inBin.map(\.maxC).max() ?? inBin[0].maxC
            let totalCount = inBin.reduce(Int64(0)) { $0 + $1.count }
            let sumC = inBin.reduce(0.0) { $0 + $1.sumC }
            let valueC = totalCount > 0 ? sumC / Double(totalCount) : inBin[0].latestC
            let latest = inBin.max(by: { $0.latestElapsedNS < $1.latestElapsedNS }) ?? inBin[0]

            output.append(
                HistoryPoint(
                    seriesID: seriesID,
                    segment: segment,
                    elapsedNS: latest.latestElapsedNS,
                    wallUnixNS: nil,
                    valueC: valueC,
                    minC: minC,
                    maxC: maxC,
                    count: totalCount
                )
            )
        }
        return output
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
}
