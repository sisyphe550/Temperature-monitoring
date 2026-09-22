import AppKit
import SwiftUI
import TemperaturePresentation

struct FatalView: View {
    let state: FatalPresentationState
    var actions: (any PresentationActions)?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: 12) {
                Text("发生致命错误")
                    .font(.headline)
                Text(state.failure.code.rawValue)
                    .font(.title3.monospaced())
                    .accessibilityIdentifier("fatal.code")
                Text(state.failure.component)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let underlying = state.failure.underlyingCode, !underlying.isEmpty {
                    Text(underlying)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("将在 \(remainingSeconds) 秒后退出")
                    .font(.subheadline)
                    .accessibilityIdentifier("fatal.countdown")
                if let reportPath = state.reportPath {
                    HStack {
                        Text(reportPath)
                            .font(.caption)
                            .lineLimit(2)
                            .textSelection(.enabled)
                        Button("复制报告路径") {
                            copyReportPath(reportPath)
                        }
                        .accessibilityIdentifier("fatal.copy")
                    }
                }
                Button("退出") {
                    actions?.quit()
                }
                .accessibilityIdentifier("fatal.quit")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var remainingSeconds: Int {
        let deadline = Date(timeIntervalSince1970: Double(state.exitDeadline.wallUnixNS) / 1_000_000_000)
        return max(0, Int(deadline.timeIntervalSinceNow.rounded(.up)))
    }

    private func copyReportPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }
}

@MainActor
enum FatalViewFallback {
    static func presentAlert(for state: FatalPresentationState) {
        let alert = NSAlert()
        alert.messageText = "温度监测发生致命错误"
        alert.informativeText = state.failure.code.rawValue
        alert.alertStyle = .critical
        alert.addButton(withTitle: "退出")
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }
}
