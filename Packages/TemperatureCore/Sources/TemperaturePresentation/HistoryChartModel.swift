import Foundation
import TemperatureCore

public struct HistoryChartPlotPoint: Sendable, Equatable {
    public let elapsedNS: Int64
    public let valueC: Double
    public let minC: Double?
    public let maxC: Double?

    public init(elapsedNS: Int64, valueC: Double, minC: Double?, maxC: Double?) {
        self.elapsedNS = elapsedNS
        self.valueC = valueC
        self.minC = minC
        self.maxC = maxC
    }
}

public struct HistoryChartPlotSegment: Sendable, Equatable, Identifiable {
    public var id: String { "\(seriesID.rawValue)-\(segment)" }
    public let seriesID: SeriesID
    public let segment: Int64
    public let displayName: String
    public let colorToken: String
    public let points: [HistoryChartPlotPoint]

    public init(
        seriesID: SeriesID,
        segment: Int64,
        displayName: String,
        colorToken: String,
        points: [HistoryChartPlotPoint]
    ) {
        self.seriesID = seriesID
        self.segment = segment
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
        case .fiveMinutes:
            return .ema
        case .oneHour:
            return .oneSecond
        case .oneDay:
            return .tenSeconds
        case .threeDays:
            return .oneMinute
        }
    }

    public static func beginLoading(previous: [HistorySeriesState]) -> HistoryChartState {
        .loading(previous: previous)
    }

    public static func makeReadyState(
        from history: HistoryResult,
        request: HistoryRequest
    ) -> HistoryChartState {
        let series = makeSeries(from: history, request: request)
        return .ready(series: series, gaps: history.gaps)
    }

    public static func makeFailedState(
        _ failure: MonitorFailure,
        previous: [HistorySeriesState]
    ) -> HistoryChartState {
        .failed(failure, previous: previous)
    }

    public static func previousSeries(from state: HistoryChartState) -> [HistorySeriesState] {
        switch state {
        case let .loading(previous):
            return previous
        case let .ready(series, _):
            return series
        case let .failed(_, previous):
            return previous
        }
    }

    public static func plotSegments(from state: HistoryChartState) -> [HistoryChartPlotSegment] {
        guard case let .ready(series, _) = state else {
            return []
        }
        return series.flatMap { plotSegments(for: $0) }
    }

    public static func peakMaxC(in state: HistoryChartState) -> Double? {
        plotSegments(from: state)
            .flatMap(\.points)
            .compactMap { point in
                if let maxC = point.maxC {
                    return maxC
                }
                return point.valueC
            }
            .max()
    }

    public static func makeSeries(
        from history: HistoryResult,
        request: HistoryRequest
    ) -> [HistorySeriesState] {
        let limitedSeriesIDs = Array(request.seriesIDs.prefix(maxSeries))
        let grouped = Dictionary(grouping: history.points, by: \.seriesID)
        return limitedSeriesIDs.compactMap { seriesID in
            guard var points = grouped[seriesID], !points.isEmpty else {
                return nil
            }
            if points.count > maxPointsPerSeries {
                points = Array(points.sorted { $0.elapsedNS < $1.elapsedNS }.suffix(maxPointsPerSeries))
            } else {
                points.sort { $0.elapsedNS < $1.elapsedNS }
            }
            return HistorySeriesState(
                seriesID: seriesID,
                displayName: seriesID.rawValue,
                colorToken: seriesID.rawValue,
                layer: history.layer,
                points: points
            )
        }
    }

    private static func plotSegments(for series: HistorySeriesState) -> [HistoryChartPlotSegment] {
        let grouped = Dictionary(grouping: series.points, by: \.segment)
        return grouped.keys.sorted().map { segment in
            let points = (grouped[segment] ?? [])
                .sorted { $0.elapsedNS < $1.elapsedNS }
                .map {
                    HistoryChartPlotPoint(
                        elapsedNS: $0.elapsedNS,
                        valueC: $0.valueC,
                        minC: $0.minC,
                        maxC: $0.maxC
                    )
                }
            return HistoryChartPlotSegment(
                seriesID: series.seriesID,
                segment: segment,
                displayName: series.displayName,
                colorToken: series.colorToken,
                points: points
            )
        }
    }
}
