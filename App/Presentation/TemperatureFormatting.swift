import Foundation
import TemperatureCore
import TemperaturePresentation

enum TemperatureFormatting {
    static let placeholder = "— °C"

    static func statusTitle(for state: PresentationState?) -> String {
        guard case let .running(running)? = state else { return placeholder }
        let value = primaryText(running.primaryCPU)
        if case .cached = running.primaryCPU { return value + " · 缓存" }
        return value
    }

    static func primaryText(_ value: TemperatureValueState) -> String {
        switch value {
        case let .live(valueC, _), let .cached(valueC, _, _):
            return String(format: "%.1f °C", valueC)
        case .loading, .stale, .unavailable: return placeholder
        }
    }

    static func rowText(_ value: TemperatureValueState) -> String { primaryText(value) }

    static func valueC(_ value: TemperatureValueState) -> Double? {
        switch value {
        case let .live(valueC, _), let .cached(valueC, _, _): return valueC
        case .loading, .stale, .unavailable: return nil
        }
    }

    static func stateDescription(_ value: TemperatureValueState) -> String {
        switch value {
        case .loading: return "正在读取"
        case let .live(_, observedAt): return "应用读取 \(time(observedAt)) · 测量更新时间未知"
        case let .cached(_, observedAt, reason): return "缓存 · 暂未更新 · \(reason) · 上次读取 \(time(observedAt))"
        case let .stale(observedAt, reason):
            return observedAt.map { "\(reason) · 上次读取 \(time($0))" } ?? reason
        case let .unavailable(_, reason): return "不可用 · \(reason)"
        }
    }

    static func time(_ timestamp: TemperatureCore.Timestamp) -> String {
        Date(timeIntervalSince1970: Double(timestamp.wallUnixNS) / 1_000_000_000)
            .formatted(date: .omitted, time: .standard)
    }

    static func periodLabel(milliseconds: Int) -> String { "\(milliseconds) ms" }
    static let cpuPeriodOptionsMS = [50, 100, 200, 500, 1000]
}
