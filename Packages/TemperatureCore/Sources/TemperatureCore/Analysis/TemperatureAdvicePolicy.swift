import Foundation

public enum TemperatureAdvicePolicy {
    public static func advice(cpu: CPUAnalysisSnapshot, systemThermalState: SystemThermalState) -> TemperatureAdvice {
        switch systemThermalState {
        case .critical: return .systemCritical
        case .serious: return .systemHot
        case .fair: return .systemWarm
        case .nominal, .unknown: break
        }
        guard case let .available(_, assessment, trend) = cpu.state else { return .awaitingCPUData }
        switch assessment {
        case .recovering: return .coolingDown
        case .sustained: return .sustainedHighTemperature
        case .pending: return .thresholdReached
        case .belowThreshold: return trend.direction == .rising ? .temperatureRising : .continueObserving
        }
    }
}
