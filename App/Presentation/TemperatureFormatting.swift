import TemperaturePresentation

enum TemperatureFormatting {
    static let placeholder = "— °C"

    static func statusTitle(for state: PresentationState?) -> String {
        guard case let .running(running)? = state else {
            return placeholder
        }
        return primaryText(running.primaryCPU)
    }

    static func primaryText(_ value: TemperatureValueState) -> String {
        switch value {
        case let .live(valueC, _), let .cached(valueC, _, _):
            return String(format: "%.1f °C", valueC)
        case .loading, .stale:
            return placeholder
        case let .unavailable(_, reason):
            return reason
        }
    }

    static func rowText(_ value: TemperatureValueState) -> String {
        switch value {
        case let .live(valueC, _), let .cached(valueC, _, _):
            return String(format: "%.1f °C", valueC)
        case .loading, .stale:
            return placeholder
        case let .unavailable(_, reason):
            return reason
        }
    }

    static func periodLabel(milliseconds: Int) -> String {
        "\(milliseconds) ms"
    }

    static let cpuPeriodOptionsMS = [50, 100, 200, 500, 1000]
}
