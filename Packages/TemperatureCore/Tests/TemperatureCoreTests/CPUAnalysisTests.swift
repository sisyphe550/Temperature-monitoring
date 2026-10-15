import Foundation
import Testing
@testable import TemperatureCore

@Suite struct CPUAnalysisTests {
    @Test(arguments: [SystemThermalState.nominal, .fair, .serious, .critical, .unknown])
    func systemStatePriorityPreservesCPUUnavailability(system: SystemThermalState) {
        let cpu = CPUAnalysisSnapshot(thresholdC: 90, durationSeconds: 5, state: .unavailable(reason: .noData))
        let result = TemperatureAnalysisSnapshot(cpu: cpu, systemThermalState: system)
        let expected: TemperatureAdvice
        switch system {
        case .critical: expected = .systemCritical
        case .serious: expected = .systemHot
        case .fair: expected = .systemWarm
        case .nominal, .unknown: expected = .awaitingCPUData
        }
        #expect(result.cpu == cpu)
        #expect(result.systemThermalState == system)
        #expect(result.advice == expected)
    }

    @Test func CPUAssessmentPriorityAndUnknownSystemUsesValidCPU() {
        let timestamp = Fixtures.timestamp(ms: 0)
        let sample = Sample(sampleID: "analysis:1", seriesID: SeriesID(Fixtures.uuid(200)), segment: 1,
            timestamp: timestamp, periodMS: 1000, valueC: 80, freshness: .unknown, sourceWallUnixNS: nil, memberSampleIDs: [])
        let cases: [(CPUThresholdAssessment, TrendDirection, TemperatureAdvice)] = [
            (.belowThreshold, .rising, .temperatureRising), (.belowThreshold, .falling, .continueObserving),
            (.belowThreshold, .stable, .continueObserving), (.belowThreshold, .insufficient, .continueObserving),
            (.pending(since: timestamp), .rising, .thresholdReached), (.sustained, .falling, .sustainedHighTemperature),
            (.recovering(since: timestamp), .rising, .coolingDown)
        ]
        for (assessment, direction, expected) in cases {
            let trend = TrendValue(seriesID: sample.seriesID, segment: 1, at: timestamp,
                slopeCPerSecond: nil, direction: direction, pointCount: 0)
            let cpu = CPUAnalysisSnapshot(thresholdC: 90, durationSeconds: 5,
                state: .available(observation: sample, assessment: assessment, trend: trend))
            #expect(TemperatureAdvicePolicy.advice(cpu: cpu, systemThermalState: .unknown) == expected)
            #expect(TemperatureAdvicePolicy.advice(cpu: cpu, systemThermalState: .nominal) == expected)
            #expect(TemperatureAdvicePolicy.advice(cpu: cpu, systemThermalState: .fair) == .systemWarm)
            #expect(TemperatureAdvicePolicy.advice(cpu: cpu, systemThermalState: .serious) == .systemHot)
            #expect(TemperatureAdvicePolicy.advice(cpu: cpu, systemThermalState: .critical) == .systemCritical)
        }
    }
}
