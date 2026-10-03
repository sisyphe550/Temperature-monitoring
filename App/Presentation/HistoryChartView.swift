import Charts
import SwiftUI
import TemperatureCore
import TemperaturePresentation

struct HistoryChartView: View, Equatable {
    let chartState: HistoryChartState
    let asOf: Timestamp?
    @State private var selectedDate: Date?

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        // Unchanged geometry ignores sub-millisecond clock jitter. Wall-clock
        // changes still update both chart coordinates and selected-point time.
        lhs.chartState == rhs.chartState && lhs.renderAnchorOffsetMS == rhs.renderAnchorOffsetMS
    }

    private nonisolated var renderAnchorOffsetMS: Int64? {
        guard let anchor = asOf else { return nil }
        let nsPerMS: Int64 = 1_000_000
        // Split before subtracting/rounding so even extreme Int64 timestamps
        // cannot overflow. Round the wall-minus-elapsed offset to the nearest ms.
        let remainder = anchor.wallUnixNS % nsPerMS - anchor.elapsedNS % nsPerMS
        let roundedRemainder = remainder + nsPerMS / 2
        let adjustment = roundedRemainder >= 0 ? roundedRemainder / nsPerMS
            : (roundedRemainder - (nsPerMS - 1)) / nsPerMS
        return anchor.wallUnixNS / nsPerMS - anchor.elapsedNS / nsPerMS + adjustment
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            chartBody.frame(maxWidth: .infinity, maxHeight: .infinity)
            selectionSummary
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.chart")
    }

    @ViewBuilder private var header: some View {
        switch chartState {
        case .loading:
            Text("正在加载历史；灰色点为上次查询结果").font(.caption).foregroundStyle(.secondary)
        case let .ready(series, gaps):
            let title = series.first?.layer == .ema ? "平滑温度（EMA）及区间范围" : "历史平均温度及已记录最低/最高"
            Text(gaps.isEmpty ? title : "\(title) · \(gaps.count)处断线")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("比较：" + series.map(\.displayName).joined(separator: "、"))
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("history.sources")
            if let peak = HistoryChartModel.peakMaxC(in: chartState) {
                Text(String(format: series.first?.layer == .ema ? "范围内最高EMA：%.1f °C" : "已记录Raw峰值：%.1f °C", peak))
                    .font(.caption).foregroundStyle(.secondary)
            }
        case let .failed(failure, previous):
            VStack(alignment: .leading, spacing: 3) {
                Text("历史加载失败：\(failure.code.rawValue)")
                if let reason = failure.underlyingCode { Text(reason) }
                if !previous.isEmpty { Text("灰色点为上次查询结果。") }
            }
            .font(.caption).foregroundStyle(.secondary)
            .accessibilityIdentifier("history.failure")
        }
    }

    @ViewBuilder private var chartBody: some View {
        switch chartState {
        case let .loading(previous), let .failed(_, previous):
            if previous.isEmpty {
                ContentUnavailableView("本会话暂无可展示数据", systemImage: "chart.xyaxis.line")
            } else {
                // Previous state carries no Gap array. Points preserve content without joining across an unknown gap.
                chart(for: HistoryChartModel.plotSegments(from: .ready(series: previous, gaps: [])), rendering: .previousPoints)
            }
        case .ready:
            let segments = HistoryChartModel.plotSegments(from: chartState)
            if segments.isEmpty {
                ContentUnavailableView("本会话暂无数据", systemImage: "chart.xyaxis.line")
            } else {
                chart(for: segments, rendering: .currentLines)
            }
        }
    }

    private enum Rendering: Equatable { case currentLines, previousPoints }

    private func chart(for segments: [HistoryChartPlotSegment], rendering: Rendering) -> some View {
        Chart(segments) { segment in
            ForEach(Array(segment.points.enumerated()), id: \.offset) { _, point in
                if rendering == .currentLines {
                    LineMark(x: .value("时间", date(for: point)), y: .value("温度", point.valueC),
                        series: .value("连续段", segment.id))
                        .foregroundStyle(by: .value("来源", segment.displayName))
                    if let minC = point.minC, let maxC = point.maxC {
                        AreaMark(x: .value("时间", date(for: point)), yStart: .value("最低", minC),
                            yEnd: .value("最高", maxC), series: .value("范围", segment.id))
                            .foregroundStyle(by: .value("来源", segment.displayName))
                            .opacity(0.15)
                    }
                    if segment.points.count == 1 {
                        PointMark(x: .value("时间", date(for: point)), y: .value("温度", point.valueC))
                            .foregroundStyle(by: .value("来源", segment.displayName))
                    }
                } else {
                    PointMark(x: .value("时间", date(for: point)), y: .value("温度", point.valueC))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
        }
        .chartYAxisLabel("°C")
        .chartXAxisLabel("时间")
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: timeAxisFormat)
            }
        }
        .chartForegroundStyleScale(range: [.blue, .orange, .green, .purple, .pink, .teal, .indigo, .brown] as [Color])
        .chartXSelection(value: $selectedDate)
        .chartLegend(position: .bottom)
    }

    @ViewBuilder private var selectionSummary: some View {
        if let selectedDate, case .ready = chartState {
            let segments = HistoryChartModel.plotSegments(from: chartState)
            let grouped = Dictionary(grouping: segments, by: \.seriesID)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(grouped.keys.sorted { $0.rawValue < $1.rawValue }, id: \.rawValue) { seriesID in
                    if let candidates = grouped[seriesID], let point = nearestPoint(in: candidates, to: selectedDate) {
                        Text(pointDescription(point, name: candidates[0].displayName))
                            .font(.caption.monospacedDigit())
                    }
                }
            }
            .accessibilityIdentifier("history.selection")
        } else {
            Text("点按曲线查看时间、温度、范围和样本数。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func nearestPoint(in segments: [HistoryChartPlotSegment], to date: Date) -> HistoryChartPlotPoint? {
        segments.flatMap(\.points).min {
            abs(self.date(for: $0).timeIntervalSince(date)) < abs(self.date(for: $1).timeIntervalSince(date))
        }
    }

    private func pointDescription(_ point: HistoryChartPlotPoint, name: String) -> String {
        let time = date(for: point).formatted(date: .abbreviated, time: .standard)
        let value = String(format: "%.1f °C", point.valueC)
        let range: String
        if let minC = point.minC, let maxC = point.maxC {
            range = String(format: " · 范围 %.1f–%.1f °C", minC, maxC)
        } else { range = "" }
        return "\(name) · \(time) · \(value)\(range) · \(point.count)个样本"
    }

    private var timeAxisFormat: Date.FormatStyle {
        if case let .ready(series, _) = chartState, series.first?.layer == .ema {
            return .dateTime.hour().minute().second()
        }
        return .dateTime.month(.twoDigits).day(.twoDigits).hour().minute()
    }

    private func date(for point: HistoryChartPlotPoint) -> Date {
        if let offsetMS = renderAnchorOffsetMS {
            let seconds = Double(offsetMS) / 1_000 + Double(point.elapsedNS) / 1_000_000_000
            return Date(timeIntervalSince1970: seconds)
        }
        let seconds = Double(point.wallUnixNS ?? point.elapsedNS) / 1_000_000_000
        return Date(timeIntervalSince1970: seconds)
    }
}

struct HistoryRangePicker: View {
    let selectedRange: HistoryRange
    let onSelect: (HistoryRange) -> Void

    var body: some View {
        HStack(spacing: 0) {
            rangeButton(title: "5 分钟", range: .fiveMinutes)
            rangeButton(title: "1 小时", range: .oneHour)
            rangeButton(title: "24 小时", range: .oneDay)
            rangeButton(title: "72 小时", range: .threeDays)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.range")
    }

    private func rangeButton(title: String, range: HistoryRange) -> some View {
        Button(title) { onSelect(range) }
            .buttonStyle(.bordered)
            .tint(selectedRange == range ? .accentColor : .secondary)
            .accessibilityIdentifier("history.range.\(title)")
    }

    static func label(for range: HistoryRange) -> String {
        switch range {
        case .fiveMinutes: return "5 分钟"
        case .oneHour: return "1 小时"
        case .oneDay: return "24 小时"
        case .threeDays: return "72 小时"
        }
    }
}
