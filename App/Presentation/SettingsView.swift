import SwiftUI
import TemperaturePresentation

struct SettingsView: View {
    @Bindable var presentationModel: PresentationModel
    var actions: (any PresentationActions)?

    var body: some View {
        Form {
            Section("CPU 采样周期") {
                CPUPeriodPicker(
                    selectedPeriodMS: currentPeriodMS,
                    onSelect: { actions?.setCPUPeriod(milliseconds: $0) }
                )
            }
            Section("温度来源") {
                sourceSummary
            }
            Section("关于") {
                LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 320)
        .padding()
    }

    private var currentPeriodMS: Int {
        if case let .running(running)? = presentationModel.state {
            return running.cpuPeriodMS
        }
        return 200
    }

    @ViewBuilder
    private var sourceSummary: some View {
        if case let .running(running)? = presentationModel.state {
            ForEach(running.sections, id: \.id) { section in
                Section(section.title) {
                    ForEach(section.rows, id: \.metricID.rawValue) { row in
                        HStack {
                            Text(row.title)
                            Spacer()
                            Text(TemperatureFormatting.rowText(row.value))
                                .font(.system(.body, design: .monospaced))
                        }
                        .accessibilityIdentifier("source.list")
                    }
                }
            }
        } else {
            Text("暂无来源数据")
                .foregroundStyle(.secondary)
        }
    }
}

struct CPUPeriodPicker: View {
    let selectedPeriodMS: Int
    let onSelect: (Int) -> Void

    var body: some View {
        Picker("CPU 周期", selection: Binding(
            get: { selectedPeriodMS },
            set: { onSelect($0) }
        )) {
            ForEach(TemperatureFormatting.cpuPeriodOptionsMS, id: \.self) { period in
                Text(TemperatureFormatting.periodLabel(milliseconds: period))
                    .tag(period)
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("cpu.period")
    }
}
