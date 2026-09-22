import Foundation
import Testing
@testable import TemperatureCore
@testable import TemperaturePresentation

@Suite struct PresentationModelTests {
    @Test @MainActor func snapshotGenerationRegressionIsRejected() throws {
        let model = try makeModel()
        let first = try sampleSnapshot(generation: 2, valueC: 70, elapsedMS: 200)
        let second = try sampleSnapshot(generation: 1, valueC: 80, elapsedMS: 400)
        #expect(model.apply(snapshot: first))
        #expect(model.apply(snapshot: second) == false)
        #expect(model.lastAppliedSnapshotGeneration == 2)
        if case let .running(running) = model.state {
            if case let .live(valueC, _) = running.primaryCPU {
                #expect(valueC == 70)
            } else {
                Issue.record("expected live primary CPU")
            }
        } else {
            Issue.record("expected running state")
        }
    }

    @Test @MainActor func fatalStateRejectsLaterRunningSnapshots() throws {
        let model = try makeModel()
        let snapshot = try sampleSnapshot(generation: 1, valueC: 70, elapsedMS: 200)
        #expect(model.apply(snapshot: snapshot))
        model.enterFatal(
            FatalDisplayReceipt(
                failure: MonitorFailure(
                    code: .sensorRead,
                    severity: .fatal,
                    component: "test",
                    operation: "read",
                    retryCount: 0,
                    sourceID: nil,
                    underlyingCode: nil
                ),
                visibleAt: Fixtures.timestamp(ms: 200),
                configuration: try Configuration.bundledDefaults(),
                reportPath: nil
            )
        )
        #expect(model.apply(snapshot: try sampleSnapshot(generation: 2, valueC: 90, elapsedMS: 400)) == false)
        if case .fatal = model.state {
            #expect(Bool(true))
        } else {
            Issue.record("expected fatal state")
        }
    }

    @Test @MainActor func valueStatesAreMutuallyExclusive() throws {
        let model = try makeModel()
        let cases: [(LatestValueState, (TemperatureValueState) -> Bool)] = [
            (.loading, { if case .loading = $0 { return true }; return false }),
            (
                .unavailable(capability: .unsupported, reason: "missing"),
                { if case .unavailable = $0 { return true }; return false }
            ),
            (
                .available(
                    ema: try emaValue(valueC: 70, ms: 200),
                    lastSuccessfulAt: Fixtures.timestamp(ms: 200),
                    lastFailure: nil
                ),
                { if case .live = $0 { return true }; return false }
            ),
            (
                .available(
                    ema: try emaValue(valueC: 70, ms: 200),
                    lastSuccessfulAt: Fixtures.timestamp(ms: 200),
                    lastFailure: MonitorFailure(
                        code: .sensorRead,
                        severity: .degraded,
                        component: "test",
                        operation: "read",
                        retryCount: 1,
                        sourceID: nil,
                        underlyingCode: "timeout"
                    )
                ),
                { if case .cached = $0 { return true }; return false }
            ),
        ]

        for (index, testCase) in cases.enumerated() {
            model.resetForTesting()
            let snapshot = try sampleSnapshot(
                generation: 1,
                valueC: 70,
                elapsedMS: 200,
                latestState: testCase.0
            )
            #expect(model.apply(snapshot: snapshot))
            if case let .running(running) = model.state {
                #expect(testCase.1(running.primaryCPU))
            } else {
                Issue.record("case \(index): expected running state")
            }
        }
    }

    @Test @MainActor func staleThresholdUsesMaxThreePeriodsOrTwoSeconds() throws {
        #expect(PresentationModel.staleThresholdNS(periodMS: 200) == 2_000_000_000)
        #expect(PresentationModel.staleThresholdNS(periodMS: 1_000) == 3_000_000_000)
    }

    @Test @MainActor func staleHidesValueAfterThreshold() throws {
        let model = try makeModel()
        let snapshot = try sampleSnapshot(
            generation: 1,
            valueC: 70,
            elapsedMS: 2_500,
            lastSuccessfulMS: 0,
            cpuPeriodMS: 200
        )
        #expect(model.apply(snapshot: snapshot))
        if case let .running(running) = model.state {
            if case .stale = running.primaryCPU {
                #expect(Bool(true))
            } else {
                Issue.record("expected stale primary CPU")
            }
        } else {
            Issue.record("expected running state")
        }
    }

    @Test @MainActor func historyChartStatesAreMutuallyExclusive() throws {
        let model = try makeModel()
        #expect(model.apply(snapshot: try sampleSnapshot(generation: 1, valueC: 70, elapsedMS: 200)))

        model.beginHistoryLoad()
        if case let .running(loadingRunning) = model.state {
            if case .loading = loadingRunning.chart {
                #expect(Bool(true))
            } else {
                Issue.record("expected loading chart")
            }
        }

        let seriesID = try SeriesID(validating: "00000000-0000-4000-8000-000000000101")
        model.apply(
            history: HistoryResult(
                layer: .ema,
                points: [
                    HistoryPoint(
                        seriesID: seriesID,
                        segment: 1,
                        elapsedNS: 200_000_000,
                        wallUnixNS: nil,
                        valueC: 70,
                        minC: nil,
                        maxC: nil,
                        count: 1
                    )
                ],
                gaps: [],
                availableFromElapsedNS: 0,
                persistedThroughElapsedNS: 200_000_000
            ),
            request: HistoryRequest(
                seriesIDs: [seriesID],
                range: .fiveMinutes,
                asOfElapsedNS: 200_000_000,
                pointLimit: 2_000
            )
        )
        if case let .running(readyRunning) = model.state {
            if case let .ready(series, _) = readyRunning.chart {
                #expect(series.count == 1)
            } else {
                Issue.record("expected ready chart")
            }
        }

        model.applyHistoryFailure(
            MonitorFailure(
                code: .databaseRead,
                severity: .fatal,
                component: "test",
                operation: "history",
                retryCount: 0,
                sourceID: nil,
                underlyingCode: "timeout"
            )
        )
        if case let .running(failedRunning) = model.state {
            if case .failed = failedRunning.chart {
                #expect(Bool(true))
            } else {
                Issue.record("expected failed chart")
            }
        }
    }
}

@MainActor
private func makeModel() throws -> PresentationModel {
    PresentationModel(primaryCPUMetricID: try MetricID(validating: "cpu.zone.max"))
}

@MainActor
private func sampleSnapshot(
    generation: UInt64,
    valueC: Double,
    elapsedMS: Int64,
    latestState: LatestValueState? = nil,
    lastSuccessfulMS: Int64? = nil,
    cpuPeriodMS: Int = 200
) throws -> Snapshot {
    let seriesID = try SeriesID(validating: "00000000-0000-4000-8000-000000000101")
    let definition = SeriesDefinition(
        seriesID: seriesID,
        metricID: try MetricID(validating: "cpu.zone.max"),
        definitionVersion: 1,
        kind: .cpuZone,
        displayName: "CPU Max",
        memberSourceIDs: [SourceID(Fixtures.uuid(1))],
        formula: .maximum
    )
    let state: LatestValueState
    if let latestState {
        state = latestState
    } else {
        state = .available(
            ema: try emaValue(valueC: valueC, ms: lastSuccessfulMS ?? elapsedMS),
            lastSuccessfulAt: Fixtures.timestamp(ms: lastSuccessfulMS ?? elapsedMS),
            lastFailure: nil
        )
    }
    return Snapshot(
        asOf: Fixtures.timestamp(ms: elapsedMS),
        values: [LatestValue(definition: definition, state: state)],
        gapIDs: [],
        cpuPeriodMS: cpuPeriodMS,
        generation: generation
    )
}

private func emaValue(valueC: Double, ms: Int64) throws -> EMAValue {
    EMAValue(
        sampleID: "fixture:1",
        seriesID: try SeriesID(validating: "00000000-0000-4000-8000-000000000101"),
        segment: 1,
        timestamp: Fixtures.timestamp(ms: ms),
        valueC: valueC
    )
}
