import SwiftUI
import TemperaturePresentation

struct TemperaturePopoverView: View {
    let presentationModel: PresentationModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("温度监测")
                .font(.headline)
            content
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 340)
        .frame(maxHeight: 640)
    }

    @ViewBuilder
    private var content: some View {
        switch presentationModel.state {
        case let .running(running):
            VStack(alignment: .leading, spacing: 12) {
                Text(primaryTemperatureText(running.primaryCPU))
                    .font(.system(.title2, design: .monospaced))
                    .accessibilityIdentifier("status.temperature")
                ForEach(running.sections, id: \.id) { section in
                    Text(section.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(section.rows, id: \.metricID.rawValue) { row in
                        HStack {
                            Text(row.title)
                            Spacer()
                            Text(rowTemperatureText(row.value))
                                .font(.system(.body, design: .monospaced))
                        }
                        .accessibilityIdentifier("source.list")
                    }
                }
            }
        case let .fatal(fatal):
            VStack(alignment: .leading, spacing: 8) {
                Text(fatal.failure.code.rawValue)
                    .accessibilityIdentifier("fatal.code")
                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
                .accessibilityIdentifier("fatal.quit")
            }
        case .none:
            Text("— °C")
                .font(.system(.title2, design: .monospaced))
        }
    }

    private func primaryTemperatureText(_ state: TemperatureValueState) -> String {
        switch state {
        case let .live(valueC, _), let .cached(valueC, _, _):
            return String(format: "%.1f °C", valueC)
        case .loading, .stale:
            return "— °C"
        case let .unavailable(_, reason):
            return reason
        }
    }

    private func rowTemperatureText(_ state: TemperatureValueState) -> String {
        switch state {
        case let .live(valueC, _), let .cached(valueC, _, _):
            return String(format: "%.1f °C", valueC)
        case .loading, .stale:
            return "— °C"
        case let .unavailable(_, reason):
            return reason
        }
    }
}
