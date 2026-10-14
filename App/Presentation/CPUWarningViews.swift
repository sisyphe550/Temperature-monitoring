import Foundation
import SwiftUI
import TemperatureCore
import TemperaturePresentation

enum CPUWarningFormatting {
    static let policy = try? Configuration.bundledDefaults().cpuWarning

    static func isActive(_ state: CPUWarningState) -> Bool {
        switch state { case .active, .recovering: return true; default: return false }
    }

    static func title(_ state: CPUWarningState) -> String {
        switch state {
        case .disabled: return "CPU预警已关闭"
        case .monitoring: return "CPU预警监测中"
        case .pending: return "持续超阈值，待触发"
        case .active: return "CPU温度预警"
        case .recovering: return "预警中，等待持续降温"
        case .unableToAssess: return "CPU预警当前无法判断"
        }
    }

    static func reason(_ reason: CPUWarningInterruptionReason) -> String {
        switch reason {
        case .noData: return "等待新的完整CPU读数"
        case .readFailure: return "CPU读取失败"
        case .gap: return "采样存在缺口"
        case .sourceChange: return "CPU来源或连续段变化"
        case .stale: return "CPU读数已过期"
        case .lifecycle: return "采集生命周期中断"
        }
    }

    static func details(_ warning: CPUWarningSnapshot, at timestamp: Timestamp) -> String {
        let rule = warning.rule
        let configured = String(format: "Raw最高温度 ≥ %.1f °C，持续%d秒", rule.thresholdC, rule.durationSeconds)
        switch warning.state {
        case .disabled: return "采样继续；开启预警后从新读数计时。"
        case .monitoring: return configured
        case .pending(let since):
            let seconds = max(0, timestamp.elapsedNS - since.elapsedNS) / 1_000_000_000
            return configured + "；已观察\(seconds)秒。"
        case .active(let eventID), .recovering(let eventID, _):
            guard let event = warning.events.first(where: { $0.eventID == eventID }) else { return configured }
            return String(format: "触发于%@；Raw事件峰值 %.1f °C；阈值 %.1f °C。",
                TemperatureFormatting.time(event.started), event.peakRawMaxC, event.thresholdC)
        case .unableToAssess(let reason): return self.reason(reason) + "；中断不代表温度恢复。"
        }
    }

    static func endDescription(_ end: CPUWarningEventEnd) -> String {
        switch end {
        case .active: return "仍在预警"
        case .ended(let at, let reason):
            let label: String
            switch reason {
            case .recovered: label = "温度恢复"
            case .disabled: label = "用户关闭预警"
            case .ruleChanged: label = "规则变更"
            case .interrupted(let why): label = "中断：" + self.reason(why)
            }
            return label + " · " + TemperatureFormatting.time(at)
        }
    }
}

struct CPUWarningStatusView: View {
    let warning: CPUWarningSnapshot
    let asOf: Timestamp
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(CPUWarningFormatting.title(warning.state), systemImage:
                CPUWarningFormatting.isActive(warning.state) ? "exclamationmark.triangle.fill" : "thermometer.medium")
                .font(.headline)
                .foregroundStyle(CPUWarningFormatting.isActive(warning.state) ? Color.orange : Color.secondary)
                .accessibilityIdentifier("warning.state")
            Text(CPUWarningFormatting.details(warning, at: asOf))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("warning.detail")
            if !compact, let policy = CPUWarningFormatting.policy {
                Text(String(format: "≤ %.1f °C持续%d秒才恢复；判断使用Raw，温度图显示EMA。",
                    warning.rule.thresholdC - policy.recoveryHysteresisC, policy.recoveryDurationSeconds))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct CPUWarningEventsView: View {
    let warning: CPUWarningSnapshot
    var body: some View {
        DisclosureGroup("本会话预警记录（\(warning.events.count)）") {
            if warning.events.isEmpty { Text("本会话尚无预警事件。") }
            ForEach(warning.events, id: \.eventID) { event in
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(format: "%@ · Raw峰值 %.1f °C", TemperatureFormatting.time(event.started), event.peakRawMaxC))
                    Text(String(format: "阈值 %.1f °C · 持续%d秒", event.thresholdC, event.durationSeconds))
                    Text(CPUWarningFormatting.endDescription(event.end)).foregroundStyle(.secondary)
                }.font(.caption).padding(.vertical, 4)
            }
        }
        .accessibilityIdentifier("warning.events")
    }
}

struct CPUWarningSettingsView: View {
    let warning: CPUWarningSnapshot
    var actions: (any PresentationActions)?
    @State private var enabled = true
    @State private var threshold = ""
    @State private var duration = ""
    @State private var notifications = false
    @State private var applying = false
    @State private var feedback: String?

    var body: some View {
        Section("CPU温度预警（点击应用后生效）") {
            Toggle("启用CPU预警", isOn: $enabled).accessibilityIdentifier("warning.enabled")
            TextField("触发温度（°C）", text: $threshold).accessibilityIdentifier("warning.threshold")
            TextField("持续时间（整数秒）", text: $duration).accessibilityIdentifier("warning.duration")
            Toggle("使用macOS系统通知", isOn: $notifications).accessibilityIdentifier("warning.notifications")
            Button(applying ? "正在应用…" : "应用预警设置", action: apply)
                .disabled(applying).accessibilityIdentifier("warning.apply")
            Text(String(format: "当前规则：%@，≥ %.1f °C持续%d秒。", warning.rule.enabled ? "启用" : "关闭",
                warning.rule.thresholdC, warning.rule.durationSeconds))
                .font(.caption).accessibilityIdentifier("warning.rule")
            if let policy = CPUWarningFormatting.policy {
                Text(String(format: "触发温度 %.0f–%.0f °C；持续%d–%d秒。恢复阈值比触发低%.0f °C，连续%d秒。",
                    policy.thresholdMinC, policy.thresholdMaxC, policy.durationMinSeconds, policy.durationMaxSeconds,
                    policy.recoveryHysteresisC, policy.recoveryDurationSeconds))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("这是用户设定的提醒规则，不是硬件安全限值。关窗后继续预警，退出后停止检测。")
                .font(.caption).foregroundStyle(.secondary)
            if let status = actions?.cpuWarningNotificationStatus() {
                Text(notificationText(status)).font(.caption).accessibilityIdentifier("warning.notification.status")
            }
            if let issue = actions?.cpuWarningPreferencesIssueText() {
                Text(issue).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("warning.preferences.issue")
            }
            if let feedback { Text(feedback).font(.caption).accessibilityIdentifier("warning.feedback") }
        }
        .onAppear(perform: loadDraft)
        .onChange(of: warning.rule) { _, _ in loadDraft() }
    }

    private func loadDraft() {
        enabled = warning.rule.enabled
        threshold = String(format: "%.1f", warning.rule.thresholdC)
        duration = String(warning.rule.durationSeconds)
        notifications = warning.rule.systemNotificationsEnabled
    }

    private func notificationText(_ status: CPUWarningNotificationStatus) -> String {
        let text: String
        switch status.authorization {
        case .notRequested: text = "系统通知尚未申请；开启并应用设置时申请。"
        case .authorized: text = "系统通知已允许；实际横幅受系统通知设置影响。"
        case .denied: text = "系统通知被拒绝；可在系统设置中允许，界面预警继续。"
        case .unavailable: text = "系统通知当前不可用，界面预警继续。"
        }
        return status.lastError == nil ? text : text + " 通知请求出错，界面预警继续。"
    }

    private func apply() {
        guard let thresholdC = Double(threshold), let seconds = Int(duration) else {
            feedback = "请输入有效温度数字和整数秒。"; return
        }
        let rule: CPUWarningRule
        do {
            rule = try CPUWarningRule(enabled: enabled, thresholdC: thresholdC,
                durationSeconds: seconds, systemNotificationsEnabled: notifications)
        } catch CPUWarningRuleError.thresholdOutOfRange {
            feedback = "触发温度必须是5–120 °C之间的有限数。"; return
        } catch { feedback = "持续时间必须是1–300之间的整数秒。"; return }
        guard let actions else { feedback = "应用尚未就绪。"; return }
        applying = true; feedback = nil
        Task { @MainActor in
            do { try await actions.applyCPUWarningRule(rule); feedback = "设置已应用并保存。" }
            catch { feedback = "设置未完全保存：\(error)" }
            applying = false
        }
    }
}
