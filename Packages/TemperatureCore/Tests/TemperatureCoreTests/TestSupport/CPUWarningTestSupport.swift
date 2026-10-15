import TemperatureCore

func testWarningSnapshot() throws -> CPUWarningSnapshot {
    CPUWarningSnapshot(rule: try Configuration.bundledDefaults().cpuWarningRule,
        state: .unableToAssess(reason: .noData), events: [])
}

func testAnalysisSnapshot() throws -> CPUAnalysisSnapshot {
    let rule = try Configuration.bundledDefaults().cpuWarningRule
    return CPUAnalysisSnapshot(thresholdC: rule.thresholdC, durationSeconds: rule.durationSeconds,
        state: .unavailable(reason: .noData))
}
