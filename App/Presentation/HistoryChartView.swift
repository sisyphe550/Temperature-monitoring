import Charts
import SwiftUI
import TemperatureCore
import TemperaturePresentation

struct HistoryChartView: View {
    let chartState: HistoryChartState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            chartBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityIdentifier("history.chart")
    }

    @ViewBuilder
    private var header: some View {
        switch chartState {
        case .loading:
            Text("正在加载历史…")
                .foregroundStyle(.secondary)
        case let .ready(_, gaps):
            if gaps.isEmpty {
                Text("历史曲线")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("历史曲线（\(gaps.count) 处断线）")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case let .failed(failure, _):
            Text(failure.code.rawValue)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var chartBody: some View {
        switch chartState {
        case let .loading(previous):
            if previous.isEmpty {
                ContentUnavailableView("本会话暂无数据", systemImage: "chart.xyaxis.line")
            } else {
                chart(for: HistoryChartModel.plotSegments(from: .ready(series: previous, gaps: [])))
                    .opacity(0.5)
            }
        case .ready:
            let segments = HistoryChartModel.plotSegments(from: chartState)
            if segments.isEmpty {
                ContentUnavailableView("本会话暂无数据", systemImage: "chart.xyaxis.line")
            } else {
                chart(for: segments)
            }
        case let .failed(_, previous):
            if previous.isEmpty {
                ContentUnavailableView("历史加载失败", systemImage: "exclamationmark.triangle")
            } else {
                chart(for: HistoryChartModel.plotSegments(from: .ready(series: previous, gaps: [])))
                    .opacity(0.5)
            }
        }
    }

    @ViewBuilder
    private func chart(for segments: [HistoryChartPlotSegment]) -> some View {
        Chart(segments) { segment in
            ForEach(Array(segment.points.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("时间", point.elapsedNS),
                    y: .value("温度", point.valueC),
                    series: .value("来源", segment.id)
                )
                if let minC = point.minC, let maxC = point.maxC, minC != maxC {
                    AreaMark(
                        x: .value("时间", point.elapsedNS),
                        yStart: .value("最低", minC),
                        yEnd: .value("最高", maxC),
                        series: .value("范围", "\(segment.id)-range")
                    )
                    .foregroundStyle(.secondary.opacity(0.15))
                }
            }
        }
        .chartYAxisLabel("°C")
        .chartXAxis(.hidden)
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
        .accessibilityIdentifier("history.range")
    }

    private func rangeButton(title: String, range: HistoryRange) -> some View {
        Button(title) {
            onSelect(range)
        }
        .buttonStyle(.bordered)
        .tint(selectedRange == range ? .accentColor : .secondary)
        .accessibilityIdentifier("history.range.\(title)")
    }

    static func label(for range: HistoryRange) -> String {
        switch range {
        case .fiveMinutes:
            return "5 分钟"
        case .oneHour:
            return "1 小时"
        case .oneDay:
            return "24 小时"
        case .threeDays:
            return "72 小时"
        }
    }
}
