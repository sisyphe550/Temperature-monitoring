import Foundation
import TemperatureCore

public struct HistoryChartPlotPoint: Sendable, Equatable {
    public let elapsedNS: Int64
    public let valueC: Double
    public let minC: Double?
    public let maxC: Double?
    public let wallUnixNS: Int64?
    public let count: Int64

    public init(elapsedNS: Int64, valueC: Double, minC: Double?, maxC: Double?, wallUnixNS: Int64? = nil, count: Int64 = 1) {
        self.elapsedNS = elapsedNS
        self.valueC = valueC
        self.minC = minC
        self.maxC = maxC
        self.wallUnixNS = wallUnixNS
        self.count = count
    }
}

public struct HistoryChartPlotSegment: Sendable, Equatable, Identifiable {
    public var id: String { "\(seriesID.rawValue)-\(segment)-\(part)" }
    public let seriesID: SeriesID
    public let segment: Int64
    public let part: Int
    public let displayName: String
    public let colorToken: String
    public let points: [HistoryChartPlotPoint]

    public init(seriesID: SeriesID, segment: Int64, displayName: String, colorToken: String, points: [HistoryChartPlotPoint], part: Int = 0) {
        self.seriesID = seriesID
        self.segment = segment
        self.part = part
        self.displayName = displayName
        self.colorToken = colorToken
        self.points = points
    }
}

public enum HistoryChartModel {
    public static let maxSeries = 8
    public static let maxPointsPerSeries = 2000

    public static func layer(for range: HistoryRange) -> HistoryLayer {
        switch range {
        case .fiveMinutes: return .ema
        case .oneHour: return .oneSecond
        case .oneDay: return .tenSeconds
        case .threeDays: return .oneMinute
        }
    }

    public static func beginLoading(previous: [HistorySeriesState]) -> HistoryChartState {
        .loading(previous: previous)
    }

    public static func makeReadyState(from history: HistoryResult, request: HistoryRequest, definitions: [SeriesDefinition] = []) -> HistoryChartState {
        do {
            return .ready(series: try makeSeries(from: history, request: request, definitions: definitions), gaps: history.gaps)
        } catch let failure as MonitorFailure {
            return .failed(failure, previous: [])
        } catch {
            return .failed(failure("历史数据无法显示：\(error)"), previous: [])
        }
    }

    public static func makeFailedState(_ failure: MonitorFailure, previous: [HistorySeriesState]) -> HistoryChartState {
        .failed(failure, previous: previous)
    }

    public static func previousSeries(from state: HistoryChartState) -> [HistorySeriesState] {
        switch state {
        case let .loading(previous), let .failed(_, previous): return previous
        case let .ready(series, _): return series
        }
    }

    public static func plotSegments(from state: HistoryChartState) -> [HistoryChartPlotSegment] {
        guard case let .ready(series, gaps) = state else { return [] }
        return series.flatMap { series in
            let applicableGaps = gaps.filter { $0.seriesID == series.seriesID }
            return connectedRuns(points: series.points, gaps: applicableGaps).enumerated().map { part, points in
                HistoryChartPlotSegment(
                    seriesID: series.seriesID, segment: points[0].segment,
                    displayName: series.displayName, colorToken: series.colorToken,
                    points: points.map {
                        HistoryChartPlotPoint(elapsedNS: $0.elapsedNS, valueC: $0.valueC,
                            minC: $0.minC, maxC: $0.maxC, wallUnixNS: $0.wallUnixNS, count: $0.count)
                    }, part: part
                )
            }
        }
    }

    public static func peakMaxC(in state: HistoryChartState) -> Double? {
        plotSegments(from: state).flatMap(\.points).map { $0.maxC ?? $0.valueC }.max()
    }

    public static func makeSeries(from history: HistoryResult, request: HistoryRequest, definitions: [SeriesDefinition] = []) throws -> [HistorySeriesState] {
        var seen: Set<SeriesID> = []
        let seriesIDs = request.seriesIDs.filter { seen.insert($0).inserted }
        guard seriesIDs.count <= maxSeries else {
            throw failure("当前范围包含超过8个来源版本；请减少比较来源或缩小时间范围。")
        }
        let limit = min(request.pointLimit, maxPointsPerSeries)
        guard limit > 0 else { throw failure("历史查询点数必须大于0。") }
        var names: [SeriesID: SeriesDefinition] = [:]
        for definition in definitions { names[definition.seriesID] = definition }
        let grouped = Dictionary(grouping: history.points, by: \.seriesID)
        return try seriesIDs.compactMap { seriesID in
            guard let points = grouped[seriesID], !points.isEmpty else { return nil }
            let gaps = history.gaps.filter { $0.seriesID == seriesID }
            let bounded = try reduce(points: points, gaps: gaps, layer: history.layer, limit: limit)
            let definition = names[seriesID]
            let displayName = definition.map { "\($0.displayName) · 来源\($0.definitionVersion)" } ?? seriesID.rawValue
            return HistorySeriesState(seriesID: seriesID, displayName: displayName,
                colorToken: definition?.metricID.rawValue ?? seriesID.rawValue,
                layer: history.layer, points: bounded)
        }
    }

    // Keep the endpoints of every continuous run. Bins never span a segment or an explicit Gap.
    private static func reduce(points: [HistoryPoint], gaps: [Gap], layer: HistoryLayer, limit: Int) throws -> [HistoryPoint] {
        let runs = connectedRuns(points: points, gaps: gaps)
        let mandatory = runs.map { min($0.count, 2) }
        let required = mandatory.reduce(0, +)
        guard required <= limit else {
            throw failure("历史断线过多，\(limit)点不足以保留各段边界；请缩小时间范围或减少比较来源。")
        }
        if points.count <= limit { return runs.flatMap { $0 } }
        let capacity = zip(runs, mandatory).map { run, endpointCount in run.count - endpointCount }
        let totalCapacity = capacity.reduce(0, +)
        let remaining = limit - required
        var budgets = mandatory
        for index in runs.indices where totalCapacity > 0 {
            budgets[index] += remaining * capacity[index] / totalCapacity
        }
        var unused = limit - budgets.reduce(0, +)
        while unused > 0 {
            for index in runs.indices where unused > 0 && budgets[index] < runs[index].count {
                budgets[index] += 1
                unused -= 1
            }
        }
        return zip(runs, budgets).flatMap { run, budget in
            reduceRun(run, layer: layer, budget: budget)
        }
    }

    private static func reduceRun(_ points: [HistoryPoint], layer: HistoryLayer, budget: Int) -> [HistoryPoint] {
        guard points.count > budget else { return points }
        let first = points[0]
        let last = points[points.count - 1]
        let binCount = budget - 2
        guard binCount > 0 else {
            // Endpoints also carry the complete interior envelope/count if no interior slot is available.
            let middle = points.count / 2
            return [merge(Array(points[..<middle]), layer: layer, representative: first),
                merge(Array(points[middle...]), layer: layer, representative: last)]
        }
        let span = max(1, last.elapsedNS - first.elapsedNS)
        var bins = [[HistoryPoint]](repeating: [], count: binCount)
        for point in points.dropFirst().dropLast() {
            let index = min(binCount - 1, Int(Double(point.elapsedNS - first.elapsedNS) / Double(span) * Double(binCount)))
            bins[max(0, index)].append(point)
        }
        let interior = bins.compactMap { bin -> HistoryPoint? in
            guard let representative = bin.last else { return nil }
            return merge(bin, layer: layer, representative: representative)
        }
        return [first] + interior + [last]
    }

    private static func merge(_ points: [HistoryPoint], layer: HistoryLayer, representative: HistoryPoint) -> HistoryPoint {
        let count = points.reduce(Int64(0)) { $0 + $1.count }
        let value: Double
        if layer == .ema || count == 0 {
            value = representative.valueC
        } else {
            value = points.reduce(0.0) { $0 + $1.valueC * Double($1.count) } / Double(count)
        }
        return HistoryPoint(seriesID: representative.seriesID, segment: representative.segment,
            elapsedNS: representative.elapsedNS, wallUnixNS: representative.wallUnixNS, valueC: value,
            minC: points.map { $0.minC ?? $0.valueC }.min(),
            maxC: points.map { $0.maxC ?? $0.valueC }.max(), count: count)
    }

    private static func connectedRuns(points: [HistoryPoint], gaps: [Gap]) -> [[HistoryPoint]] {
        let ordered = points.sorted {
            $0.elapsedNS == $1.elapsedNS ? $0.segment < $1.segment : $0.elapsedNS < $1.elapsedNS
        }
        var runs: [[HistoryPoint]] = []
        for point in ordered {
            if let previous = runs.last?.last {
                let crossesGap = gaps.contains { gap in
                    gap.startedElapsedNS < point.elapsedNS && (gap.endedElapsedNS ?? Int64.max) > previous.elapsedNS
                }
                if previous.segment == point.segment && !crossesGap {
                    runs[runs.count - 1].append(point)
                    continue
                }
            }
            runs.append([point])
        }
        return runs
    }

    private static func failure(_ reason: String) -> MonitorFailure {
        MonitorFailure(code: .uiData, severity: .degraded, component: "HistoryChartModel",
            operation: "history", retryCount: 0, sourceID: nil, underlyingCode: reason)
    }
}
