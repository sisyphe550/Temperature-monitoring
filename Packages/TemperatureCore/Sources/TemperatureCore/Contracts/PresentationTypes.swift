import Foundation

public enum LatestValueState: Sendable, Equatable {
    case loading
    case available(
        ema: EMAValue,
        lastSuccessfulAt: Timestamp,
        lastFailure: MonitorFailure?
    )
    case unavailable(capability: Capability, reason: String)
}

public struct LatestValue: Sendable, Equatable {
    public let definition: SeriesDefinition
    public let state: LatestValueState

    public init(definition: SeriesDefinition, state: LatestValueState) {
        self.definition = definition
        self.state = state
    }
}

public struct Snapshot: Sendable, Equatable {
    public let asOf: Timestamp
    public let values: [LatestValue]
    public let gapIDs: [GapID]
    public let cpuPeriodMS: Int
    public let generation: UInt64

    public init(
        asOf: Timestamp,
        values: [LatestValue],
        gapIDs: [GapID],
        cpuPeriodMS: Int,
        generation: UInt64
    ) {
        self.asOf = asOf
        self.values = values
        self.gapIDs = gapIDs
        self.cpuPeriodMS = cpuPeriodMS
        self.generation = generation
    }
}

public struct HistoryRequest: Sendable, Equatable {
    public let seriesIDs: [SeriesID]
    public let range: HistoryRange
    public let asOfElapsedNS: Int64
    public let pointLimit: Int

    public init(
        seriesIDs: [SeriesID],
        range: HistoryRange,
        asOfElapsedNS: Int64,
        pointLimit: Int
    ) {
        self.seriesIDs = seriesIDs
        self.range = range
        self.asOfElapsedNS = asOfElapsedNS
        self.pointLimit = pointLimit
    }
}

public struct HistoryPoint: Sendable, Equatable {
    public let seriesID: SeriesID
    public let segment: Int64
    public let elapsedNS: Int64
    public let wallUnixNS: Int64?
    public let valueC: Double
    public let minC: Double?
    public let maxC: Double?
    public let count: Int64

    public init(
        seriesID: SeriesID,
        segment: Int64,
        elapsedNS: Int64,
        wallUnixNS: Int64?,
        valueC: Double,
        minC: Double?,
        maxC: Double?,
        count: Int64
    ) {
        self.seriesID = seriesID
        self.segment = segment
        self.elapsedNS = elapsedNS
        self.wallUnixNS = wallUnixNS
        self.valueC = valueC
        self.minC = minC
        self.maxC = maxC
        self.count = count
    }
}

public struct HistoryResult: Sendable, Equatable {
    public let layer: HistoryLayer
    public let points: [HistoryPoint]
    public let gaps: [Gap]
    public let availableFromElapsedNS: Int64?
    public let persistedThroughElapsedNS: Int64?

    public init(
        layer: HistoryLayer,
        points: [HistoryPoint],
        gaps: [Gap],
        availableFromElapsedNS: Int64?,
        persistedThroughElapsedNS: Int64?
    ) {
        self.layer = layer
        self.points = points
        self.gaps = gaps
        self.availableFromElapsedNS = availableFromElapsedNS
        self.persistedThroughElapsedNS = persistedThroughElapsedNS
    }
}

public enum TemperatureValueState: Sendable, Equatable {
    case loading
    case live(valueC: Double, observedAt: Timestamp)
    case cached(valueC: Double, observedAt: Timestamp, reason: String)
    case stale(lastObservedAt: Timestamp?, reason: String)
    case unavailable(capability: Capability, reason: String)
}

public enum TemperatureSectionID: String, Codable, Sendable, Equatable {
    case cpu
    case ssd
    case battery
}

public struct TemperatureRowState: Sendable, Equatable {
    public let sourceID: SourceID?
    public let metricID: MetricID
    public let title: String
    public let evidence: EvidenceLevel
    public let value: TemperatureValueState

    public init(
        sourceID: SourceID?,
        metricID: MetricID,
        title: String,
        evidence: EvidenceLevel,
        value: TemperatureValueState
    ) {
        self.sourceID = sourceID
        self.metricID = metricID
        self.title = title
        self.evidence = evidence
        self.value = value
    }
}

public struct TemperatureSectionState: Sendable, Equatable {
    public let id: TemperatureSectionID
    public let title: String
    public let rows: [TemperatureRowState]

    public init(id: TemperatureSectionID, title: String, rows: [TemperatureRowState]) {
        self.id = id
        self.title = title
        self.rows = rows
    }
}

public struct HistorySeriesState: Sendable, Equatable {
    public let seriesID: SeriesID
    public let displayName: String
    public let colorToken: String
    public let layer: HistoryLayer
    public let points: [HistoryPoint]

    public init(
        seriesID: SeriesID,
        displayName: String,
        colorToken: String,
        layer: HistoryLayer,
        points: [HistoryPoint]
    ) {
        self.seriesID = seriesID
        self.displayName = displayName
        self.colorToken = colorToken
        self.layer = layer
        self.points = points
    }
}

public enum HistoryChartState: Sendable, Equatable {
    case loading(previous: [HistorySeriesState])
    case ready(series: [HistorySeriesState], gaps: [Gap])
    case failed(MonitorFailure, previous: [HistorySeriesState])
}

public struct RunningPresentationState: Sendable, Equatable {
    public let asOf: Timestamp
    public let cpuPeriodMS: Int
    public let primaryCPU: TemperatureValueState
    public let sections: [TemperatureSectionState]
    public let chart: HistoryChartState

    public init(
        asOf: Timestamp,
        cpuPeriodMS: Int,
        primaryCPU: TemperatureValueState,
        sections: [TemperatureSectionState],
        chart: HistoryChartState
    ) {
        self.asOf = asOf
        self.cpuPeriodMS = cpuPeriodMS
        self.primaryCPU = primaryCPU
        self.sections = sections
        self.chart = chart
    }
}

public struct FatalPresentationState: Sendable, Equatable {
    public let failure: MonitorFailure
    public let reportPath: String?
    public let exitDeadline: Timestamp

    public init(failure: MonitorFailure, reportPath: String?, exitDeadline: Timestamp) {
        self.failure = failure
        self.reportPath = reportPath
        self.exitDeadline = exitDeadline
    }
}

public enum PresentationState: Sendable, Equatable {
    case running(RunningPresentationState)
    case fatal(FatalPresentationState)
}

public protocol MonitorClock: Sendable {
    func now() -> Timestamp
    func sleep(untilElapsedNS: Int64) async throws
}
