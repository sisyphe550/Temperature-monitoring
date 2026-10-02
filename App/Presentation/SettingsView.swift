import AppKit
import SwiftUI
import TemperaturePresentation

struct SettingsView: View {
    @Bindable var presentationModel: PresentationModel
    var actions: (any PresentationActions)?

    var body: some View {
        Group {
            if case let .fatal(fatal) = presentationModel.state {
                FatalView(state: fatal, actions: actions)
            } else {
                Form {
                    if case let .running(running) = presentationModel.state {
                        Section("CPU 采样周期") {
                            CPUPeriodPicker(selectedPeriodMS: running.cpuPeriodMS,
                                onSelect: { actions?.setCPUPeriod(milliseconds: $0) })
                        }
                    }
                    Section("温度来源") { sourceSummary }
                    Section("诊断") {
                        Button("打开日志目录") { NSWorkspace.shared.open(logDirectory) }
                            .accessibilityIdentifier("settings.logs")
                        Button("打开错误报告目录") {
                            NSWorkspace.shared.open(logDirectory.appendingPathComponent("reports", isDirectory: true))
                        }
                        .accessibilityIdentifier("settings.reports")
                    }
                    Section("关于") {
                        LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                        if let notices = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "md") {
                            Button("第三方许可与声明") { NSWorkspace.shared.open(notices) }
                                .accessibilityIdentifier("settings.licenses")
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .frame(minWidth: 440, minHeight: 460)
        .padding()
    }

    private var logDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleID = (try? AppBundleConfiguration.loadRuntimeConfiguration().bundleID) ?? Bundle.main.bundleIdentifier ?? "io.github.sisyphe550.TemperatureMonitor"
        return support.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    @ViewBuilder private var sourceSummary: some View {
        if case let .running(running) = presentationModel.state {
            ForEach(running.sections, id: \.id) { section in
                Text(section.title).font(.subheadline).foregroundStyle(.secondary)
                ForEach(section.rows, id: \.metricID.rawValue) { row in TemperatureSourceRow(row: row) }
            }
            Text("悬停来源可查看身份、指标和映射依据。测量更新时间未知；显示的是应用读取时间。")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Text("暂无来源数据").foregroundStyle(.secondary)
        }
    }
}

struct CPUPeriodPicker: View {
    let selectedPeriodMS: Int
    let onSelect: (Int) -> Void

    var body: some View {
        Picker("CPU 周期", selection: Binding(get: { selectedPeriodMS }, set: { onSelect($0) })) {
            ForEach(TemperatureFormatting.cpuPeriodOptionsMS, id: \.self) { period in
                Text(TemperatureFormatting.periodLabel(milliseconds: period)).tag(period)
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("cpu.period")
    }
}
