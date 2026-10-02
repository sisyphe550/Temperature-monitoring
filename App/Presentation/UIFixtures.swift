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
        case "cached":
            applyCached(to: model)
        case "unavailable":
            applyUnavailable(to: model)
        case "fatal":
            applyFatal(to: model)
        default:
            break
        }
    }

    static func applyBasic(to model: PresentationModel, cpuPeriodMS: Int, generation: UInt64) {
        let now = Timestamp(elapsedNS: 300_000_000_000, wallUnixNS: 1_700_000_300_000_000_000)
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

    static func applySources(to model: PresentationModel, cpuPeriodMS: Int = 200, generation: UInt64 = 1) {
        let now = Timestamp(elapsedNS: 300_000_000_000, wallUnixNS: 1_700_000_300_000_000_000)
        let temperatures = [61.2, 55.0, 42.5, 31.0]
        let values = sourceDefinitions().enumerated().map { index, definition in
            makeLatest(definition: definition, valueC: temperatures[index], at: now)
        }
        _ = model.apply(snapshot: Snapshot(asOf: now, values: values, gapIDs: [],
            cpuPeriodMS: cpuPeriodMS, generation: generation))
    }

    private static func sourceDefinitions() -> [SeriesDefinition] {
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
        return [cpuMax, cpuMember, ssd, battery]
    }

    static func applyCached(to model: PresentationModel) {
        let definition = sourceDefinitions()[0]
        let observed = Timestamp(elapsedNS: 1_000_000_000, wallUnixNS: 1_700_000_001_000_000_000)
        let now = Timestamp(elapsedNS: 1_500_000_000, wallUnixNS: 1_700_000_001_500_000_000)
        let failure = MonitorFailure(code: .sensorRead, severity: .degraded, component: "fixture",
            operation: "read", retryCount: 1, sourceID: nil, underlyingCode: "timeout")
        let latest = LatestValue(definition: definition, state: .available(
            ema: EMAValue(sampleID: "fixture:cached", seriesID: definition.seriesID, segment: 1,
                timestamp: observed, valueC: 58.3), lastSuccessfulAt: observed, lastFailure: failure))
        _ = model.apply(snapshot: Snapshot(asOf: now, values: [latest], gapIDs: [], cpuPeriodMS: 200, generation: 1))
    }

    static func applyUnavailable(to model: PresentationModel) {
        let now = Timestamp(elapsedNS: 300_000_000_000, wallUnixNS: 1_700_000_300_000_000_000)
        let definitions = sourceDefinitions()
        let values = [makeLatest(definition: definitions[0], valueC: 61.2, at: now),
            LatestValue(definition: definitions[2], state: .unavailable(capability: .unsupported,
                reason: "当前设备未发现可读取的SSD温度来源"))]
        _ = model.apply(snapshot: Snapshot(asOf: now, values: values, gapIDs: [], cpuPeriodMS: 200, generation: 1))
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

    static func applyHistory(to model: PresentationModel, range: HistoryRange, metricIDs: Set<MetricID> = []) {
        let selected = metricIDs.isEmpty ? Set([try! MetricID(validating: "cpu.zone.max")]) : metricIDs
        let definitions = sourceDefinitions().filter { selected.contains($0.metricID) }
        let layer = HistoryChartModel.layer(for: range)
        let pointCount = switch range {
        case .fiveMinutes: 30
        case .oneHour: 60
        case .oneDay: 80
        case .threeDays: 100
        }
        guard case let .running(running) = model.state else { return }
        let asOf = running.asOf.elapsedNS
        let durationNS: Int64 = switch range {
        case .fiveMinutes: 300_000_000_000
        case .oneHour: 3_600_000_000_000
        case .oneDay: 86_400_000_000_000
        case .threeDays: 259_200_000_000_000
        }
        let startNS = max(0, asOf - durationNS)
        var points: [HistoryPoint] = []
        for (sourceIndex, definition) in definitions.enumerated() {
            for index in 0..<pointCount {
                let elapsedNS = startNS + Int64(Double(asOf - startNS) * Double(index) / Double(pointCount - 1))
                let valueC = 50.0 - Double(sourceIndex * 10) + Double(index % 10)
                let maxC = index == pointCount / 2 ? valueC + 15 : valueC
                points.append(HistoryPoint(seriesID: definition.seriesID,
                    segment: index < pointCount / 2 ? 1 : 2, elapsedNS: elapsedNS,
                    wallUnixNS: nil, valueC: valueC, minC: valueC, maxC: maxC, count: 1))
            }
        }
        model.beginHistoryLoad()
        model.apply(history: HistoryResult(layer: layer, points: points, gaps: [],
            availableFromElapsedNS: startNS, persistedThroughElapsedNS: asOf),
            request: HistoryRequest(seriesIDs: definitions.map(\.seriesID), range: range,
                asOfElapsedNS: asOf, pointLimit: 2000), definitions: definitions)
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
