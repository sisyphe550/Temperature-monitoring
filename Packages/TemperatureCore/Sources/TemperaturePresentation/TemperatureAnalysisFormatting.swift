import Foundation
import TemperatureCore

/// Text for the Core analysis; this layer does not evaluate temperatures or choose advice.
public enum TemperatureAnalysisFormatting {
    public static func systemText(_ state: SystemThermalState) -> String {
        switch state {
        case .nominal: return "系统热状态正常（macOS报告）"
        case .fair: return "系统热状态偏高（macOS报告）"
        case .serious: return "系统热状态严重（macOS报告）"
        case .critical: return "系统热状态危急（macOS报告）"
        case .unknown: return "系统热状态未知"
        }
    }

    public static func rawText(_ cpu: CPUAnalysisSnapshot) -> String {
        guard case let .available(observation, _, _) = cpu.state else {
            return "CPU热区Raw最高温度：无法判断"
        }
        return String(format: "CPU热区Raw最高温度：%.1f °C", observation.valueC)
    }

    public static func assessmentText(_ cpu: CPUAnalysisSnapshot) -> String {
        let rule = String(format: "参考规则：≥ %.1f °C持续%d秒", cpu.thresholdC, cpu.durationSeconds)
        guard case let .available(observation, assessment, _) = cpu.state else {
            if case let .unavailable(reason) = cpu.state {
                return "CPU当前无法判断：" + interruptionText(reason) + "；缺测不代表恢复。"
            }
            return "CPU当前无法判断"
        }
        switch assessment {
        case .belowThreshold:
            return "CPU未达到设定阈值；" + rule + "。"
        case .pending(let since):
            return "CPU达到设定阈值，待持续确认；" + rule
                + "；已观察" + observedSeconds(since: since, through: observation.timestamp) + "秒。"
        case .sustained:
            return "CPU曾持续达到设定阈值，尚未满足恢复条件；" + rule + "。"
        case .recovering(let since):
            return "CPU恢复观察中；已观察" + observedSeconds(since: since, through: observation.timestamp)
                + "秒；需连续满足恢复规则，缺测不算恢复。"
        }
    }

    public static func trendText(_ cpu: CPUAnalysisSnapshot) -> String {
        guard case let .available(_, _, trend) = cpu.state else {
            return "近10秒EMA趋势：数据不足（CPU读数无效）"
        }
        let direction: String
        switch trend.direction {
        case .rising: direction = "上升"
        case .stable: direction = "平稳"
        case .falling: direction = "下降"
        case .insufficient: return "近10秒EMA趋势：数据不足"
        }
        guard let slope = trend.slopeCPerSecond, slope.isFinite else { return "近10秒EMA趋势：数据不足" }
        return "近10秒EMA趋势：" + direction + String(format: "（%+.3f °C/s）", slope)
    }

    public static func adviceText(_ advice: TemperatureAdvice) -> String {
        switch advice {
        case .awaitingCPUData:
            return "等待新的完整有效CPU读数后再判断；缺测不代表温度恢复。"
        case .continueObserving:
            return "继续观察温度与趋势；保持通风，按当前工作负载使用。"
        case .temperatureRising:
            return "温度正在上升；留意后续变化，可在活动监视器查看持续占用CPU的进程。"
        case .thresholdReached:
            return "已达到设定阈值，等待持续确认；关注温度与负载，可查看活动监视器。"
        case .sustainedHighTemperature:
            return "曾持续达到设定阈值且尚未恢复；可减少持续负载、查看活动监视器并保持通风。"
        case .coolingDown:
            return "温度已进入恢复观察；继续观察，等待连续满足恢复规则。"
        case .systemWarm:
            return "macOS报告整机热状态偏高；留意持续负载并保持通风。"
        case .systemHot:
            return "macOS报告整机热状态严重；建议减少持续负载，查看活动监视器并保持通风。"
        case .systemCritical:
            return "macOS报告整机热状态危急；建议尽快减少持续负载，保持通风并观察系统状态。"
        }
    }

    private static func observedSeconds(since: Timestamp, through observation: Timestamp) -> String {
        let elapsed = max(0, Double(observation.elapsedNS) - Double(since.elapsedNS)) / 1_000_000_000
        return String(format: "%.1f", elapsed)
    }

    private static func interruptionText(_ reason: CPUWarningInterruptionReason) -> String {
        switch reason {
        case .noData: return "等待新的完整CPU读数"
        case .readFailure: return "CPU读取失败或成员不齐"
        case .gap: return "采样存在缺口"
        case .sourceChange: return "CPU来源或连续段变化"
        case .stale: return "CPU读数已过期"
        case .lifecycle: return "采集生命周期中断"
        }
    }
}
