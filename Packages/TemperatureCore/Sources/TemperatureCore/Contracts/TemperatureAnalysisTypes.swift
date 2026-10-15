import Foundation

public enum CPUThresholdAssessment: Sendable, Equatable {
    case belowThreshold
    case pending(since: Timestamp)
    case sustained
    case recovering(since: Timestamp)
}

public enum CPUAnalysisState: Sendable, Equatable {
    case unavailable(reason: CPUWarningInterruptionReason)
    case available(observation: Sample, assessment: CPUThresholdAssessment, trend: TrendValue)
}

public struct CPUAnalysisSnapshot: Sendable, Equatable {
    public let thresholdC: Double
    public let durationSeconds: Int
    public let state: CPUAnalysisState

    public init(thresholdC: Double, durationSeconds: Int, state: CPUAnalysisState) {
        self.thresholdC = thresholdC
        self.durationSeconds = durationSeconds
        self.state = state
    }
}

public enum SystemThermalState: Sendable, Equatable {
    case nominal, fair, serious, critical, unknown
}

public enum TemperatureAdvice: Sendable, Equatable {
    case awaitingCPUData, continueObserving, temperatureRising, thresholdReached
    case sustainedHighTemperature, coolingDown, systemWarm, systemHot, systemCritical
}


public struct TemperatureAnalysisSnapshot: Sendable, Equatable {
    public let cpu: CPUAnalysisSnapshot
    public let systemThermalState: SystemThermalState
    public let advice: TemperatureAdvice

    public init(cpu: CPUAnalysisSnapshot, systemThermalState: SystemThermalState) {
        self.cpu = cpu
        self.systemThermalState = systemThermalState
        self.advice = TemperatureAdvicePolicy.advice(cpu: cpu, systemThermalState: systemThermalState)
    }
}
