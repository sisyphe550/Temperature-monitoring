import SwiftUI
import TemperatureCore
import TemperaturePresentation

struct TemperatureDashboard: View {
    @Bindable var presentationModel: PresentationModel
    var actions: (any PresentationActions)?

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
            Text("温度监测")
                .font(.headline)
            CPUPeriodPicker(
                selectedPeriodMS: currentPeriodMS,
                onSelect: { actions?.setCPUPeriod(milliseconds: $0) }
            )
            Spacer()
            Button("设置") {
                actions?.openSettings()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch presentationModel.state {
        case let .running(running):
            HSplitView {
                sourceList(running)
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
                chartArea(running)
            }
        case let .fatal(fatal):
            FatalView(state: fatal, actions: actions)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .none:
            Text("正在读取…")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var currentPeriodMS: Int {
        if case let .running(running)? = presentationModel.state {
            return running.cpuPeriodMS
        }
        return 200
    }

    @ViewBuilder
    private func sourceList(_ running: RunningPresentationState) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                overviewRow(title: "CPU", value: running.primaryCPU)
                ForEach(running.sections, id: \.id) { section in
                    Text(section.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(section.rows, id: \.metricID.rawValue) { row in
                        TemperatureSourceRow(row: row)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func chartArea(_ running: RunningPresentationState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HistoryRangePicker(
                selectedRange: actions?.currentHistoryRange() ?? .fiveMinutes,
                onSelect: { actions?.setHistoryRange($0) }
            )
            HistoryChartView(chartState: running.chart)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func overviewRow(title: String, value: TemperatureValueState) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Text(TemperatureFormatting.primaryText(value))
                .font(.system(.title3, design: .monospaced))
                .accessibilityIdentifier("status.temperature")
        }
    }
}
