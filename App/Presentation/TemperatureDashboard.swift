import Charts
import SwiftUI
import TemperatureCore
import TemperaturePresentation

struct TemperatureDashboard: View {
    @Bindable var presentationModel: PresentationModel
    var actions: (any PresentationActions)?
    private static let primaryMetricID = try! MetricID(validating: "cpu.zone.max")

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(minWidth: 800, minHeight: 560)
    }

    private var toolbar: some View {
        HStack(spacing: 16) {
            Text("温度监测").font(.headline)
            if case let .running(running) = presentationModel.state {
                CPUPeriodPicker(selectedPeriodMS: running.cpuPeriodMS,
                    onSelect: { actions?.setCPUPeriod(milliseconds: $0) })
                Spacer()
                Button("设置") { actions?.openSettings() }
                Button("退出") { actions?.quit() }
                    .accessibilityIdentifier("app.quit")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    @ViewBuilder private var content: some View {
        switch presentationModel.state {
        case let .running(running):
            HSplitView {
                sourceList(running).frame(minWidth: 240, idealWidth: 300, maxWidth: 380)
                chartArea(running)
            }
        case let .fatal(fatal):
            FatalView(state: fatal, actions: actions)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .none:
            Text("正在读取…").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func sourceList(_ running: RunningPresentationState) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("历史比较（最多8个来源版本）").font(.caption).foregroundStyle(.secondary)
                Toggle(isOn: selection(Self.primaryMetricID)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("CPU热区最高温度").font(.headline)
                        Text(TemperatureFormatting.primaryText(running.primaryCPU))
                            .font(.system(.title3, design: .monospaced))
                            .accessibilityIdentifier("status.temperature")
                        Text(TemperatureFormatting.stateDescription(running.primaryCPU))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("history.select.cpu.zone.max")
                .disabled(selectionDisabled(Self.primaryMetricID))
                ForEach(running.sections, id: \.id) { section in
                    Text(section.title).font(.subheadline).foregroundStyle(.secondary)
                    ForEach(section.rows, id: \.metricID.rawValue) { row in
                        Toggle(isOn: selection(row.metricID)) { TemperatureSourceRow(row: row) }
                            .toggleStyle(.checkbox)
                            .accessibilityIdentifier("history.select.\(row.metricID.rawValue)")
                            .accessibilityLabel(Text("\(row.title), \(TemperatureFormatting.rowText(row.value)), \(TemperatureFormatting.stateDescription(row.value))"))
                            .disabled(selectionDisabled(row.metricID) || isUnavailable(row.value))
                    }
                }
                Text("来源重连会单独分段；图例显示来源版本，曲线不跨断线连接。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func selection(_ metricID: MetricID) -> Binding<Bool> {
        Binding(get: { selectedMetrics.contains(metricID) }, set: { isSelected in
            var updated = selectedMetrics
            if isSelected { updated.insert(metricID) } else { updated.remove(metricID) }
            guard !updated.isEmpty, updated.count <= HistoryChartModel.maxSeries else { return }
            actions?.setHistoryMetricIDs(updated)
        })
    }

    private var selectedMetrics: Set<MetricID> {
        actions?.currentHistoryMetricIDs() ?? [Self.primaryMetricID]
    }

    private func selectionDisabled(_ metricID: MetricID) -> Bool {
        let selected = selectedMetrics
        return (!selected.contains(metricID) && selected.count >= HistoryChartModel.maxSeries)
            || (selected.contains(metricID) && selected.count == 1)
    }

    private func isUnavailable(_ value: TemperatureValueState) -> Bool {
        if case .unavailable = value { return true }
        return false
    }

    private func chartArea(_ running: RunningPresentationState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HistoryRangePicker(selectedRange: actions?.currentHistoryRange() ?? .fiveMinutes,
                onSelect: { actions?.setHistoryRange($0) })
            HistoryChartView(chartState: running.chart, asOf: running.asOf)
                .frame(minHeight: 220)
            Divider()
            temperatureComparison(running)
        }
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func temperatureComparison(_ running: RunningPresentationState) -> some View {
        let values = comparisonValues(running)
        return VStack(alignment: .leading, spacing: 6) {
            Text("当前温度比较（EMA）").font(.subheadline)
            if values.isEmpty {
                Text("暂无有效温度。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    Chart(values, id: \.id) { item in
                        BarMark(x: .value("温度", item.valueC), y: .value("来源", item.title))
                            .foregroundStyle(.blue)
                            .annotation(position: .trailing) {
                                Text(String(format: "%.1f °C", item.valueC)).font(.caption.monospacedDigit())
                            }
                    }
                    .chartXAxisLabel("°C")
                    .frame(height: CGFloat(max(120, values.count * 25)))
                }
                .frame(maxHeight: 175)
            }
        }
        .accessibilityIdentifier("temperature.comparison")
    }

    private struct ComparisonValue {
        let id: String
        let title: String
        let valueC: Double
    }

    private func comparisonValues(_ running: RunningPresentationState) -> [ComparisonValue] {
        var values: [ComparisonValue] = []
        if let temperature = TemperatureFormatting.valueC(running.primaryCPU) {
            values.append(ComparisonValue(id: "cpu.zone.max", title: "CPU热区最高温度", valueC: temperature))
        }
        for row in running.sections.flatMap(\.rows) {
            if let temperature = TemperatureFormatting.valueC(row.value) {
                values.append(ComparisonValue(id: row.metricID.rawValue, title: row.title, valueC: temperature))
            }
        }
        return values
    }
}
