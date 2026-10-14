import TemperatureCore

func testWarningSnapshot() throws -> CPUWarningSnapshot {
    CPUWarningSnapshot(rule: try Configuration.bundledDefaults().cpuWarningRule,
        state: .unableToAssess(reason: .noData), events: [])
}
