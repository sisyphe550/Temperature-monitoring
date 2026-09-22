import AppKit
import SwiftUI
import TemperaturePresentation

struct TemperaturePopoverView: View {
    @Bindable var presentationModel: PresentationModel
    var actions: (any PresentationActions)?
    var onClose: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            scrollContent
                .frame(maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 340, height: 640)
        .onExitCommand(perform: onClose)
    }

    private var header: some View {
        HStack {
            Text("温度监测")
                .font(.headline)
            Spacer()
            Button("设置") {
                actions?.openSettings()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.entry")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch presentationModel.state {
        case let .running(running):
            runningContent(running)
        case let .fatal(fatal):
            fatalContent(fatal)
        case .none:
            Text(TemperatureFormatting.placeholder)
                .font(.system(.title2, design: .monospaced))
                .accessibilityIdentifier("status.temperature")
        }
    }

    @ViewBuilder
    private func runningContent(_ running: RunningPresentationState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(TemperatureFormatting.primaryText(running.primaryCPU))
                .font(.system(.title2, design: .monospaced))
                .accessibilityIdentifier("status.temperature")
            ForEach(Array(running.sections.enumerated()), id: \.element.id) { index, section in
                if index > 0 {
                    Divider()
                }
                Text(section.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(section.rows, id: \.metricID.rawValue) { row in
                    TemperatureSourceRow(row: row)
                }
            }
        }
    }

    @ViewBuilder
    private func fatalContent(_ fatal: FatalPresentationState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(fatal.failure.code.rawValue)
                .font(.headline)
                .accessibilityIdentifier("fatal.code")
            if let reportPath = fatal.reportPath {
                Text(reportPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Button("退出") {
                actions?.quit()
            }
            .accessibilityIdentifier("fatal.quit")
        }
    }

    private var footer: some View {
        HStack {
            Button("打开主窗口") {
                actions?.openDashboard()
            }
            .accessibilityIdentifier("dashboard.open")
            Spacer()
            Button("退出") {
                actions?.quit()
            }
            .accessibilityIdentifier("app.quit")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
