import Foundation
import Observation
import TemperatureCore

@MainActor
@Observable
public final class PresentationModel {
    public private(set) var state: PresentationState?
    public private(set) var lastAppliedSnapshotGeneration: UInt64 = 0

    private let primaryCPUMetricID: MetricID
    private var chartState: HistoryChartState = .loading(previous: [])
    private var currentDefinitions: [SeriesDefinition] = []

    public init(primaryCPUMetricID: MetricID) {
        self.primaryCPUMetricID = primaryCPUMetricID
    }

    @discardableResult
    public func apply(snapshot: Snapshot) -> Bool {
        if case .fatal = state {
            return false
        }
        guard snapshot.generation >= lastAppliedSnapshotGeneration else {
            return false
        }
        lastAppliedSnapshotGeneration = snapshot.generation
        currentDefinitions = snapshot.values.map(\.definition)
        let running = makeRunningState(from: snapshot)
        state = .running(running)
        return true
    }

    public func beginHistoryLoad() {
        if case .fatal = state {
            return
        }
        chartState = HistoryChartModel.beginLoading(previous: chartPreviousSeries())
        if case let .running(running) = state {
            state = .running(
                RunningPresentationState(
                    asOf: running.asOf,
                    cpuPeriodMS: running.cpuPeriodMS,
                    primaryCPU: running.primaryCPU,
                    sections: running.sections,
                    chart: chartState
                )
            )
        }
    }

    public func apply(history: HistoryResult, request: HistoryRequest, definitions: [SeriesDefinition] = []) {
        if case .fatal = state {
            return
        }
        let next = HistoryChartModel.makeReadyState(from: history, request: request,
            definitions: currentDefinitions + definitions)
        if case let .failed(failure, _) = next {
            chartState = HistoryChartModel.makeFailedState(failure, previous: chartPreviousSeries())
        } else {
            chartState = next
        }
        refreshRunningChart()
    }

    public func applyHistoryFailure(_ failure: MonitorFailure) {
        if case .fatal = state {
            return
        }
        chartState = HistoryChartModel.makeFailedState(failure, previous: chartPreviousSeries())
        refreshRunningChart()
    }

    public func enterFatal(_ receipt: FatalDisplayReceipt) {
        state = .fatal(
            FatalPresentationState(
                failure: receipt.failure,
                reportPath: receipt.reportPath,
                exitDeadline: receipt.exitDeadline
            )
        )
    }

    public func resetForTesting() {
        currentDefinitions = []
        lastAppliedSnapshotGeneration = 0
        chartState = .loading(previous: [])
        state = nil
    }

    private func refreshRunningChart() {
        guard case let .running(running) = state else {
            return
        }
        state = .running(
            RunningPresentationState(
                asOf: running.asOf,
                cpuPeriodMS: running.cpuPeriodMS,
                primaryCPU: running.primaryCPU,
                sections: running.sections,
                chart: chartState
            )
        )
    }

    private func makeRunningState(from snapshot: Snapshot) -> RunningPresentationState {
        let sections = makeSections(from: snapshot)
        let primaryCPU = primaryCPUValue(from: snapshot)
        return RunningPresentationState(
            asOf: snapshot.asOf,
            cpuPeriodMS: snapshot.cpuPeriodMS,
            primaryCPU: primaryCPU,
            sections: sections,
            chart: chartState
        )
    }

    private func primaryCPUValue(from snapshot: Snapshot) -> TemperatureValueState {
        if let match = snapshot.values.first(where: { $0.definition.metricID == primaryCPUMetricID }) {
            return convert(
                match,
                asOf: snapshot.asOf,
                cpuPeriodMS: snapshot.cpuPeriodMS
            )
        }
        if let derived = snapshot.values.first(where: {
            $0.definition.formula == .maximum && $0.definition.kind == .cpuZone
        }) {
            return convert(
                derived,
                asOf: snapshot.asOf,
                cpuPeriodMS: snapshot.cpuPeriodMS
            )
        }
        return .loading
    }

    private func makeSections(from snapshot: Snapshot) -> [TemperatureSectionState] {
        let cpuRows = rows(for: [.cpuZone, .cpuMain], in: snapshot)
        let ssdRows = rows(for: [.ssd], in: snapshot)
        let batteryRows = rows(for: [.battery], in: snapshot)
        var sections: [TemperatureSectionState] = []
        if !cpuRows.isEmpty {
            sections.append(TemperatureSectionState(id: .cpu, title: "CPU", rows: cpuRows))
        }
        if !ssdRows.isEmpty {
            sections.append(TemperatureSectionState(id: .ssd, title: "SSD", rows: ssdRows))
        }
        if !batteryRows.isEmpty {
            sections.append(TemperatureSectionState(id: .battery, title: "Battery", rows: batteryRows))
        }
        return sections
    }

    private func rows(for kinds: [SensorKind], in snapshot: Snapshot) -> [TemperatureRowState] {
        snapshot.values
            .filter { kinds.contains($0.definition.kind) && $0.definition.formula == .identity }
            .sorted { $0.definition.displayName < $1.definition.displayName }
            .map { latest in
                TemperatureRowState(
                    sourceID: latest.definition.memberSourceIDs.first,
                    metricID: latest.definition.metricID,
                    title: latest.definition.displayName,
                    evidence: .referenceClassified,
                    value: convert(
                        latest,
                        asOf: snapshot.asOf,
                        cpuPeriodMS: snapshot.cpuPeriodMS
                    )
                )
            }
    }

    private func convert(
        _ latest: LatestValue,
        asOf: Timestamp,
        cpuPeriodMS: Int
    ) -> TemperatureValueState {
        switch latest.state {
        case .loading:
            return .loading
        case let .unavailable(capability, reason):
            return .unavailable(capability: capability, reason: reason)
        case let .available(ema, lastSuccessfulAt, lastFailure):
            let periodMS: Int
            switch latest.definition.kind {
            case .battery: periodMS = 1000
            case .ssd: periodMS = 500
            default: periodMS = cpuPeriodMS
            }
            let staleThresholdNS = Self.staleThresholdNS(periodMS: periodMS)
            let ageNS = asOf.elapsedNS - lastSuccessfulAt.elapsedNS
            if ageNS > staleThresholdNS {
                return .stale(
                    lastObservedAt: lastSuccessfulAt,
                    reason: lastFailure.map { "数据已过期：\($0.code.rawValue) \($0.underlyingCode ?? "")" } ?? "数据已过期"
                )
            }
            if let lastFailure {
                return .cached(
                    valueC: ema.valueC,
                    observedAt: lastSuccessfulAt,
                    reason: "\(lastFailure.code.rawValue) \(lastFailure.underlyingCode ?? "")"
                )
            }
            return .live(valueC: ema.valueC, observedAt: lastSuccessfulAt)
        }
    }

    private func chartPreviousSeries() -> [HistorySeriesState] {
        HistoryChartModel.previousSeries(from: chartState)
    }

    public static func staleThresholdNS(periodMS: Int) -> Int64 {
        max(Int64(periodMS) * 3, 2_000) * 1_000_000
    }
}
