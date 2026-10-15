import Foundation
import Testing
@testable import TemperatureCore
@testable import TemperaturePresentation

@Suite struct TemperatureAnalysisPresentationTests {
    @Test(arguments: [
        (ProcessInfo.ThermalState.nominal.rawValue, SystemThermalState.nominal),
        (ProcessInfo.ThermalState.fair.rawValue, SystemThermalState.fair),
        (ProcessInfo.ThermalState.serious.rawValue, SystemThermalState.serious),
        (ProcessInfo.ThermalState.critical.rawValue, SystemThermalState.critical),
        (Int.max, SystemThermalState.unknown),
    ])
    func providerMapsSystemStates(input: Int, expected: SystemThermalState) {
        let provider: any SystemThermalStateProviding = ProcessInfoThermalStateProvider(readRawState: { input })
        #expect(provider.currentState() == expected)
    }

    @Test @MainActor func omittedSystemStateIsUnknownAndRawIsDistinctFromEMA() throws {
        let model = try model()
        let cpu = try analysis(rawC: 95, assessment: .sustained)
        #expect(model.apply(snapshot: try snapshot(generation: 1, cpu: cpu)))
        let running = try running(model)
        #expect(running.analysis.cpu == cpu)
        #expect(running.analysis.systemThermalState == .unknown)
        #expect(running.analysis.advice == .sustainedHighTemperature)
        #expect(running.primaryCPU == .live(valueC: 58.3, observedAt: at(20)))
        #expect(TemperatureAnalysisFormatting.rawText(cpu).contains("95.0 °C"))
    }

    @Test @MainActor func nominalSystemWithMissingCPUStillCannotAssessCPU() throws {
        let model = try model()
        let cpu = CPUAnalysisSnapshot(thresholdC: 90, durationSeconds: 5, state: .unavailable(reason: .stale))
        #expect(model.apply(snapshot: try snapshot(generation: 1, cpu: cpu), systemThermalState: .nominal))
        let displayed = try running(model).analysis
        #expect(displayed.cpu == cpu)
        #expect(displayed.advice == .awaitingCPUData)
        #expect(TemperatureAnalysisFormatting.systemText(displayed.systemThermalState) == "系统热状态正常（macOS报告）")
        #expect(TemperatureAnalysisFormatting.assessmentText(cpu).contains("无法判断"))
        #expect(TemperatureAnalysisFormatting.trendText(cpu) == "近10秒EMA趋势：数据不足（CPU读数无效）")
        #expect(TemperatureAnalysisFormatting.adviceText(displayed.advice).contains("等待"))
    }

    @Test @MainActor func explicitSystemStateUsesCoreAdvicePolicy() throws {
        let cpu = try analysis(rawC: 70, assessment: .belowThreshold)
        let model = try model()
        #expect(model.apply(snapshot: try snapshot(generation: 1, cpu: cpu), systemThermalState: .serious))
        let displayed = try running(model).analysis
        #expect(displayed == TemperatureAnalysisSnapshot(cpu: cpu, systemThermalState: .serious))
        #expect(displayed.advice == .systemHot)
        #expect(TemperatureAnalysisFormatting.adviceText(displayed.advice).contains("减少持续负载"))
    }

    @Test @MainActor func historyLoadingReadyAndFailedPreserveExactAnalysis() throws {
        let model = try model()
        let cpu = try analysis(rawC: 84, assessment: .recovering(since: at(16)))
        #expect(model.apply(snapshot: try snapshot(generation: 1, cpu: cpu), systemThermalState: .fair))
        let expected = try running(model).analysis
        model.beginHistoryLoad()
        #expect(try running(model).analysis == expected)
        let seriesID = try seriesID()
        model.apply(history: HistoryResult(layer: .ema, points: [], gaps: [],
            availableFromElapsedNS: 0, persistedThroughElapsedNS: 20_000_000_000),
            request: HistoryRequest(seriesIDs: [seriesID], range: .fiveMinutes,
                asOfElapsedNS: 20_000_000_000, pointLimit: 2_000))
        #expect(try running(model).analysis == expected)
        model.applyHistoryFailure(failure())
        #expect(try running(model).analysis == expected)
    }

    @Test @MainActor func oldGenerationCannotReplaceAnalysisOrSystemState() throws {
        let model = try model()
        let cpu = try analysis(rawC: 95, assessment: .sustained)
        #expect(model.apply(snapshot: try snapshot(generation: 2, cpu: cpu), systemThermalState: .critical))
        let expected = try running(model).analysis
        let older = try snapshot(generation: 1, cpu: analysis(rawC: 40, assessment: .belowThreshold))
        #expect(model.apply(snapshot: older, systemThermalState: .nominal) == false)
        #expect(try running(model).analysis == expected)
    }

    @Test @MainActor func fatalRejectsSnapshotAndHistoryAnalysisUpdates() throws {
        let model = try model()
        #expect(model.apply(snapshot: try snapshot(generation: 1, cpu: analysis(rawC: 95, assessment: .sustained)),
            systemThermalState: .serious))
        model.enterFatal(FatalDisplayReceipt(failure: failure(), visibleAt: at(20),
            configuration: try Configuration.bundledDefaults(), reportPath: nil))
        let fatal = model.state
        #expect(model.apply(snapshot: try snapshot(generation: 2, cpu: analysis(rawC: 30, assessment: .belowThreshold)),
            systemThermalState: .nominal) == false)
        model.beginHistoryLoad()
        model.applyHistoryFailure(failure())
        #expect(model.state == fatal)
    }

    @Test func pendingAndRecoveryProgressUseLastRawObservation() throws {
        let pending = try analysis(rawC: 95, assessment: .pending(since: at(16)))
        #expect(TemperatureAnalysisFormatting.assessmentText(pending).contains("已观察4.0秒"))
        let recovering = try analysis(rawC: 84, assessment: .recovering(since: at(16)))
        #expect(TemperatureAnalysisFormatting.assessmentText(recovering).contains("已观察4.0秒"))
        #expect(TemperatureAnalysisFormatting.assessmentText(recovering).contains("恢复观察"))
    }

    @Test @MainActor func snapshotRefreshDoesNotAddUnobservedPendingTime() throws {
        let model = try model()
        let cpu = try analysis(rawC: 95, assessment: .pending(since: at(16)))
        #expect(model.apply(snapshot: try snapshot(generation: 1, cpu: cpu), systemThermalState: .nominal))
        #expect(model.apply(snapshot: try snapshot(generation: 1, cpu: cpu, asOfSeconds: 22), systemThermalState: .nominal))
        let displayed = try running(model).analysis
        #expect(displayed.cpu == cpu)
        #expect(TemperatureAnalysisFormatting.assessmentText(displayed.cpu).contains("已观察4.0秒"))
        #expect(!TemperatureAnalysisFormatting.assessmentText(displayed.cpu).contains("已观察6.0秒"))
    }

    @Test func sustainedBelowTriggerDescribesPriorEventAndUnfinishedRecovery() throws {
        let cpu = try analysis(rawC: 88, assessment: .sustained)
        let text = TemperatureAnalysisFormatting.assessmentText(cpu)
        #expect(text.contains("曾持续达到设定阈值"))
        #expect(text.contains("尚未满足恢复条件"))
        #expect(!text.contains("当前Raw达到"))
    }

    @Test(arguments: [TrendDirection.rising, .stable, .falling, .insufficient])
    func trendLabelsKeepDirectionAndRateUnits(direction: TrendDirection) throws {
        let cpu = try analysis(rawC: 70, assessment: .belowThreshold, direction: direction)
        let text = TemperatureAnalysisFormatting.trendText(cpu)
        switch direction {
        case .rising: #expect(text.contains("上升") && text.contains("°C/s"))
        case .stable: #expect(text.contains("平稳") && text.contains("°C/s"))
        case .falling: #expect(text.contains("下降") && text.contains("°C/s"))
        case .insufficient: #expect(text == "近10秒EMA趋势：数据不足")
        }
    }

    @Test(arguments: [SystemThermalState.nominal, .fair, .serious, .critical, .unknown])
    func systemLabelsRespectWholeSystemScope(state: SystemThermalState) {
        let text = TemperatureAnalysisFormatting.systemText(state)
        #expect(text.contains("系统热状态"))
        #expect(!text.contains("CPU安全"))
        if state == .unknown { #expect(text.contains("未知") && !text.contains("正常")) }
    }

    @Test(arguments: [
        (TemperatureAdvice.awaitingCPUData, "等待新的完整有效CPU读数"),
        (.continueObserving, "继续观察"), (.temperatureRising, "温度正在上升"),
        (.thresholdReached, "等待持续确认"), (.sustainedHighTemperature, "曾持续达到设定阈值且尚未恢复"),
        (.coolingDown, "恢复观察"), (.systemWarm, "整机热状态偏高"),
        (.systemHot, "整机热状态严重"), (.systemCritical, "整机热状态危急"),
    ])
    func everyCoreAdviceHasActionableDisplay(advice: TemperatureAdvice, expectedMeaning: String) {
        let text = TemperatureAnalysisFormatting.adviceText(advice)
        #expect(text.contains(expectedMeaning))
        #expect(!text.contains("硬件损坏") && !text.contains("自动关闭"))
    }

    private func at(_ seconds: Int64) -> Timestamp {
        Timestamp(elapsedNS: seconds * 1_000_000_000, wallUnixNS: (1_700_000_000 + seconds) * 1_000_000_000)
    }

    @MainActor private func model() throws -> PresentationModel {
        PresentationModel(primaryCPUMetricID: try MetricID(validating: "cpu.zone.max"))
    }

    @MainActor private func running(_ model: PresentationModel) throws -> RunningPresentationState {
        guard case let .running(value) = model.state else { throw TestFailure.expectedRunning }
        return value
    }

    private func seriesID() throws -> SeriesID { try SeriesID(validating: "00000000-0000-4000-8000-000000000101") }

    private func analysis(rawC: Double, assessment: CPUThresholdAssessment,
        direction: TrendDirection = .stable) throws -> CPUAnalysisSnapshot {
        let seriesID = try seriesID()
        let observation = Sample(sampleID: "analysis:raw", seriesID: seriesID, segment: 1,
            timestamp: at(20), periodMS: 200, valueC: rawC, freshness: .unknown,
            sourceWallUnixNS: nil, memberSampleIDs: ["cpu12:complete"])
        let slope: Double? = direction == .insufficient ? nil : direction == .rising ? 0.1 : direction == .falling ? -0.1 : 0
        return CPUAnalysisSnapshot(thresholdC: 90, durationSeconds: 5,
            state: .available(observation: observation, assessment: assessment,
                trend: TrendValue(seriesID: seriesID, segment: 1, at: at(20),
                    slopeCPerSecond: slope, direction: direction, pointCount: direction == .insufficient ? 2 : 10)))
    }

    private func snapshot(generation: UInt64, cpu: CPUAnalysisSnapshot, asOfSeconds: Int64 = 21) throws -> Snapshot {
        let seriesID = try seriesID()
        let definition = SeriesDefinition(seriesID: seriesID, metricID: try MetricID(validating: "cpu.zone.max"),
            definitionVersion: 1, kind: .cpuZone, displayName: "CPU Max", memberSourceIDs: [], formula: .maximum)
        let ema = EMAValue(sampleID: "analysis:ema", seriesID: seriesID, segment: 1, timestamp: at(20), valueC: 58.3)
        return Snapshot(asOf: at(asOfSeconds), values: [LatestValue(definition: definition,
            state: .available(ema: ema, lastSuccessfulAt: at(20), lastFailure: nil))], gapIDs: [],
            cpuPeriodMS: 200, generation: generation,
            warning: CPUWarningSnapshot(rule: try Configuration.bundledDefaults().cpuWarningRule,
                state: .disabled, events: []), analysis: cpu)
    }

    private func failure() -> MonitorFailure {
        MonitorFailure(code: .databaseRead, severity: .fatal, component: "test", operation: "history",
            retryCount: 0, sourceID: nil, underlyingCode: "fixture")
    }

    private enum TestFailure: Error { case expectedRunning }
}
