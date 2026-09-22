import Foundation
import TemperatureCore
import TemperaturePresentation

@MainActor
enum UIFixtures {
    static func apply(named name: String, to model: PresentationModel) {
        switch name {
        case "basic":
            applyBasic(to: model, cpuPeriodMS: 200, generation: 1)
            applyHistory(to: model, range: .fiveMinutes)
        case "sources":
            applySources(to: model)
            applyHistory(to: model, range: .fiveMinutes)
        case "stale":
            applyStale(to: model)
        case "fatal":
            applyFatal(to: model)
        default:
            break
        }
    }

    static func applyBasic(to model: PresentationModel, cpuPeriodMS: Int, generation: UInt64) {
        let now = Timestamp(elapsedNS: 200_000_000, wallUnixNS: 1_700_000_000_200_000_000)
        let seriesID = (try? SeriesID(validating: "00000000-0000-4000-8000-000000000101"))!
        let definition = SeriesDefinition(
            seriesID: seriesID,
            metricID: (try? MetricID(validating: "cpu.zone.max"))!,
            definitionVersion: 1,
            kind: .cpuZone,
            displayName: "CPU Max",
            memberSourceIDs: [(try? SourceID(validating: "00000000-0000-4000-8000-000000000001"))!],
            formula: .maximum
        )
        _ = model.apply(
            snapshot: Snapshot(
                asOf: now,
                values: [
                    LatestValue(
                        definition: definition,
                        state: .available(
                            ema: EMAValue(
                                sampleID: "fixture:1",
                                seriesID: seriesID,
                                segment: 1,
                                timestamp: now,
                                valueC: 58.3
                            ),
                            lastSuccessfulAt: now,
                            lastFailure: nil
                        )
                    )
                ],
                gapIDs: [],
                cpuPeriodMS: cpuPeriodMS,
                generation: generation
            )
        )
    }

    static func applySources(to model: PresentationModel) {
        let now = Timestamp(elapsedNS: 500_000_000, wallUnixNS: 1_700_000_000_500_000_000)
        let cpuMax = makeDefinition(
            seriesUUID: "00000000-0000-4000-8000-000000000101",
            metricID: "cpu.zone.max",
            kind: .cpuZone,
            displayName: "CPU Max",
            sourceUUID: "00000000-0000-4000-8000-000000000001",
            formula: .maximum
        )
        let cpuMember = makeDefinition(
            seriesUUID: "00000000-0000-4000-8000-000000000102",
            metricID: "cpu.member.tp01",
            kind: .cpuMain,
            displayName: "Tp01",
            sourceUUID: "00000000-0000-4000-8000-000000000002",
            formula: .identity
        )
        let ssd = makeDefinition(
            seriesUUID: "00000000-0000-4000-8000-000000000201",
            metricID: "ssd.temp",
            kind: .ssd,
            displayName: "SSD",
            sourceUUID: "00000000-0000-4000-8000-000000000003",
            formula: .identity
        )
        let battery = makeDefinition(
            seriesUUID: "00000000-0000-4000-8000-000000000301",
            metricID: "battery.temp",
            kind: .battery,
            displayName: "Battery",
            sourceUUID: "00000000-0000-4000-8000-000000000004",
            formula: .identity
        )
        _ = model.apply(
            snapshot: Snapshot(
                asOf: now,
                values: [
                    makeLatest(definition: cpuMax, valueC: 61.2, at: now),
                    makeLatest(definition: cpuMember, valueC: 55.0, at: now),
                    makeLatest(definition: ssd, valueC: 42.5, at: now),
                    makeLatest(definition: battery, valueC: 31.0, at: now)
                ],
                gapIDs: [],
                cpuPeriodMS: 200,
                generation: 1
            )
        )
    }

    static func applyStale(to model: PresentationModel) {
        let now = Timestamp(elapsedNS: 5_000_000_000, wallUnixNS: 1_700_000_005_000_000_000)
        let lastSuccess = Timestamp(elapsedNS: 0, wallUnixNS: 1_700_000_000_000_000_000)
        let seriesID = (try? SeriesID(validating: "00000000-0000-4000-8000-000000000101"))!
        let definition = SeriesDefinition(
            seriesID: seriesID,
            metricID: (try? MetricID(validating: "cpu.zone.max"))!,
            definitionVersion: 1,
            kind: .cpuZone,
            displayName: "CPU Max",
            memberSourceIDs: [(try? SourceID(validating: "00000000-0000-4000-8000-000000000001"))!],
            formula: .maximum
        )
        _ = model.apply(
            snapshot: Snapshot(
                asOf: now,
                values: [
                    LatestValue(
                        definition: definition,
                        state: .available(
                            ema: EMAValue(
                                sampleID: "fixture:stale",
                                seriesID: seriesID,
                                segment: 1,
                                timestamp: lastSuccess,
                                valueC: 70.0
                            ),
                            lastSuccessfulAt: lastSuccess,
                            lastFailure: nil
                        )
                    )
                ],
                gapIDs: [],
                cpuPeriodMS: 200,
                generation: 1
            )
        )
    }

    static func applyFatal(to model: PresentationModel) {
        applyBasic(to: model, cpuPeriodMS: 200, generation: 1)
        let nowWallNS = Int64(Date().timeIntervalSince1970 * 1_000_000_000)
        model.enterFatal(
            FatalDisplayReceipt(
                failure: MonitorFailure(
                    code: .sensorRead,
                    severity: .fatal,
                    component: "fixture",
                    operation: "read",
                    retryCount: 3,
                    sourceID: nil,
                    underlyingCode: "timeout"
                ),
                visibleAt: Timestamp(elapsedNS: 200_000_000, wallUnixNS: nowWallNS),
                configuration: (try? Configuration.bundledDefaults())!,
                reportPath: "/tmp/temperature-monitor-fixture-report.json"
            )
        )
    }

    private static func makeDefinition(
        seriesUUID: String,
        metricID: String,
        kind: SensorKind,
        displayName: String,
        sourceUUID: String,
        formula: SeriesFormula
    ) -> SeriesDefinition {
        SeriesDefinition(
            seriesID: (try? SeriesID(validating: seriesUUID))!,
            metricID: (try? MetricID(validating: metricID))!,
            definitionVersion: 1,
            kind: kind,
            displayName: displayName,
            memberSourceIDs: [(try? SourceID(validating: sourceUUID))!],
            formula: formula
        )
    }

    static func applyHistory(to model: PresentationModel, range: HistoryRange) {
        let seriesID = (try? SeriesID(validating: "00000000-0000-4000-8000-000000000101"))!
        let layer = HistoryChartModel.layer(for: range)
        let pointCount = switch range {
        case .fiveMinutes: 30
        case .oneHour: 60
        case .oneDay: 80
        case .threeDays: 100
        }
        var points: [HistoryPoint] = []
        points.reserveCapacity(pointCount)
        for index in 0 ..< pointCount {
            let elapsedMS = Int64(100 + index * 100)
            let valueC = 50.0 + Double(index % 10)
            let maxC = index == pointCount / 2 ? 95.0 : valueC
            points.append(
                HistoryPoint(
                    seriesID: seriesID,
                    segment: index < pointCount / 2 ? 1 : 2,
                    elapsedNS: elapsedMS * 1_000_000,
                    wallUnixNS: nil,
                    valueC: valueC,
                    minC: min(valueC, maxC),
                    maxC: maxC,
                    count: 1
                )
            )
        }
        model.beginHistoryLoad()
        model.apply(
            history: HistoryResult(
                layer: layer,
                points: points,
                gaps: [],
                availableFromElapsedNS: 100_000_000,
                persistedThroughElapsedNS: Int64(100 + pointCount * 100) * 1_000_000
            ),
            request: HistoryRequest(
                seriesIDs: [seriesID],
                range: range,
                asOfElapsedNS: Int64(100 + pointCount * 100) * 1_000_000,
                pointLimit: 2000
            )
        )
    }

    private static func makeLatest(
        definition: SeriesDefinition,
        valueC: Double,
        at timestamp: Timestamp
    ) -> LatestValue {
        LatestValue(
            definition: definition,
            state: .available(
                ema: EMAValue(
                    sampleID: "fixture:\(definition.metricID.rawValue)",
                    seriesID: definition.seriesID,
                    segment: 1,
                    timestamp: timestamp,
                    valueC: valueC
                ),
                lastSuccessfulAt: timestamp,
                lastFailure: nil
            )
        )
    }
}
