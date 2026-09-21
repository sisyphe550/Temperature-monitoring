// Design contract family v1, contract revision 2. Not the production implementation.
// Copy into Packages/TemperatureCore and split by the file map in docs/08.
import Foundation

public enum SensorKind: String, Codable, Sendable, Equatable {
    case cpuMain
    case cpuZone
    case ssd
    case battery
}

public enum ProviderKind: String, Codable, Sendable, Equatable {
    case smc
    case hid
    case nvme
    case iops
}

public enum EvidenceLevel: String, Codable, Sendable, Equatable {
    case referenceClassified
    case targetQualified
    case unknown
}

public enum Capability: String, Codable, Sendable, Equatable {
    case available
    case unsupported
    case permissionDenied
    case mappingUnknown
    case failed
}

public enum Freshness: String, Codable, Sendable, Equatable {
    case unknown
    case sourceTimestamp
}

public enum GapReason: String, Codable, Sendable, Equatable {
    case readFailure
    case sleep
    case overload
    case sourceChange
    case clockChange
    case timeout
}

public enum SegmentReason: String, Codable, Sendable, Equatable {
    case sessionStart
    case sourceChange
    case wake
    case clockChange
    case recovery
    case gap
}

public enum SeriesFormula: String, Codable, Sendable, Equatable {
    case identity
    case maximum
}

public enum TrendDirection: String, Codable, Sendable, Equatable {
    case rising
    case falling
    case stable
    case insufficient
}

public enum Severity: String, Codable, Sendable, Equatable {
    case capability
    case degraded
    case fatal
}

public enum HistoryRange: Int64, Codable, Sendable, Equatable {
    case fiveMinutes = 300
    case oneHour = 3600
    case oneDay = 86400
    case threeDays = 259200
}

public enum HistoryLayer: String, Codable, Sendable, Equatable {
    case ema
    case oneSecond
    case tenSeconds
    case oneMinute
}

public enum MonitorErrorCode: String, Codable, Sendable, Equatable {
    case appInit = "APP-INIT-001"
    case unsupportedPlatform = "APP-PLATFORM-002"
    case sensorDiscover = "SENSOR-DISCOVER-001"
    case sensorRead = "SENSOR-READ-002"
    case sensorValue = "SENSOR-VALUE-003"
    case sensorTag = "SENSOR-TAG-004"
    case sensorTimeout = "SENSOR-TIMEOUT-005"
    case sensorProtocol = "SENSOR-PROTOCOL-006"
    case databaseOpen = "DB-OPEN-001"
    case databaseInit = "DB-INIT-002"
    case databaseWrite = "DB-WRITE-003"
    case databaseRead = "DB-READ-004"
    case databaseClean = "DB-CLEAN-005"
    case databaseCorrupt = "DB-CORRUPT-006"
    case databaseSchema = "DB-SCHEMA-007"
    case databaseBackpressure = "DB-BACKPRESSURE-008"
    case databaseCapacity = "DB-CAPACITY-009"
    case databaseIntegrity = "DB-INTEGRITY-010"
    case processingValidate = "PROC-VALIDATE-001"
    case processingEMA = "PROC-EMA-002"
    case processingAggregate = "PROC-AGG-003"
    case processingTrend = "PROC-TREND-004"
    case uiData = "UI-DATA-001"
    case uiRender = "UI-RENDER-002"
}

public enum IdentifierError: Error, Sendable, Equatable {
    case nonCanonicalUUID(String)
    case emptyMetricID
    case invalidMetricID(String)
}

public struct TaggedUUID<Tag>: Codable, Sendable, Hashable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        guard
            let uuid = UUID(uuidString: rawValue),
            uuid.uuidString.lowercased() == rawValue
        else {
            throw IdentifierError.nonCanonicalUUID(rawValue)
        }
        self.rawValue = rawValue
    }

    public init(_ uuid: UUID) {
        self.rawValue = uuid.uuidString.lowercased()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(validating: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum SessionIDTag: Sendable {}
public enum SourceIDTag: Sendable {}
public enum SeriesIDTag: Sendable {}
public enum RequestIDTag: Sendable {}
public enum BatchIDTag: Sendable {}
public enum GapIDTag: Sendable {}
public enum WatermarkEventIDTag: Sendable {}

public typealias SessionID = TaggedUUID<SessionIDTag>
public typealias SourceID = TaggedUUID<SourceIDTag>
public typealias SeriesID = TaggedUUID<SeriesIDTag>
public typealias RequestID = TaggedUUID<RequestIDTag>
public typealias BatchID = TaggedUUID<BatchIDTag>
public typealias GapID = TaggedUUID<GapIDTag>
public typealias WatermarkEventID = TaggedUUID<WatermarkEventIDTag>

public struct MetricID: Codable, Sendable, Hashable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        guard !rawValue.isEmpty else {
            throw IdentifierError.emptyMetricID
        }
        guard rawValue.range(of: #"^[a-z][a-z0-9]*(?:\.[a-z0-9]+)*$"#, options: .regularExpression) != nil else {
            throw IdentifierError.invalidMetricID(rawValue)
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(validating: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct Timestamp: Codable, Sendable, Equatable {
    public let elapsedNS: Int64
    public let wallUnixNS: Int64

    public init(elapsedNS: Int64, wallUnixNS: Int64) {
        self.elapsedNS = elapsedNS
        self.wallUnixNS = wallUnixNS
    }
}

public struct SessionMetadata: Codable, Sendable, Equatable {
    public let sessionID: SessionID
    public let startedWallUnixNS: Int64
    public let model: String
    public let osBuild: String
    public let appVersion: String

    public init(
        sessionID: SessionID,
        startedWallUnixNS: Int64,
        model: String,
        osBuild: String,
        appVersion: String
    ) {
        self.sessionID = sessionID
        self.startedWallUnixNS = startedWallUnixNS
        self.model = model
        self.osBuild = osBuild
        self.appVersion = appVersion
    }
}

public struct DiscoveredSource: Codable, Sendable, Equatable {
    public let transportHandle: String
    public let provider: ProviderKind
    public let rawKey: String
    public let registryID: String?
    public let encoding: String
    public let byteCount: Int

    public init(
        transportHandle: String,
        provider: ProviderKind,
        rawKey: String,
        registryID: String?,
        encoding: String,
        byteCount: Int
    ) {
        self.transportHandle = transportHandle
        self.provider = provider
        self.rawKey = rawKey
        self.registryID = registryID
        self.encoding = encoding
        self.byteCount = byteCount
    }
}

public struct DiscoveredCatalog: Codable, Sendable, Equatable {
    public let generation: UInt64
    public let sources: [DiscoveredSource]

    public init(generation: UInt64, sources: [DiscoveredSource]) {
        self.generation = generation
        self.sources = sources
    }
}

public struct QualifiedSource: Codable, Sendable, Equatable {
    public let sourceID: SourceID
    public let transportHandle: String
    public let provider: ProviderKind
    public let rawKey: String
    public let registryID: String?
    public let connectionGeneration: UInt64
    public let kind: SensorKind
    public let encoding: String
    public let unitEvidence: String
    public let evidence: EvidenceLevel
    public let mappingVersion: String

    public init(
        sourceID: SourceID,
        transportHandle: String,
        provider: ProviderKind,
        rawKey: String,
        registryID: String?,
        connectionGeneration: UInt64,
        kind: SensorKind,
        encoding: String,
        unitEvidence: String,
        evidence: EvidenceLevel,
        mappingVersion: String
    ) {
        self.sourceID = sourceID
        self.transportHandle = transportHandle
        self.provider = provider
        self.rawKey = rawKey
        self.registryID = registryID
        self.connectionGeneration = connectionGeneration
        self.kind = kind
        self.encoding = encoding
        self.unitEvidence = unitEvidence
        self.evidence = evidence
        self.mappingVersion = mappingVersion
    }
}

public struct SourceCapabilityRecord: Codable, Sendable, Equatable {
    public let provider: ProviderKind
    public let rawKey: String?
    public let registryID: String?
    public let intendedKind: SensorKind?
    public let capability: Capability
    public let reason: String

    public init(
        provider: ProviderKind,
        rawKey: String?,
        registryID: String?,
        intendedKind: SensorKind?,
        capability: Capability,
        reason: String
    ) {
        self.provider = provider
        self.rawKey = rawKey
        self.registryID = registryID
        self.intendedKind = intendedKind
        self.capability = capability
        self.reason = reason
    }
}

public struct QualifiedSourceCatalog: Codable, Sendable, Equatable {
    public let generation: UInt64
    public let available: [QualifiedSource]
    public let unavailable: [SourceCapabilityRecord]

    public init(
        generation: UInt64,
        available: [QualifiedSource],
        unavailable: [SourceCapabilityRecord]
    ) {
        self.generation = generation
        self.available = available
        self.unavailable = unavailable
    }
}

public struct SeriesDefinition: Codable, Sendable, Equatable {
    public let seriesID: SeriesID
    public let metricID: MetricID
    public let definitionVersion: Int
    public let kind: SensorKind
    public let displayName: String
    public let memberSourceIDs: [SourceID]
    public let formula: SeriesFormula

    public init(
        seriesID: SeriesID,
        metricID: MetricID,
        definitionVersion: Int,
        kind: SensorKind,
        displayName: String,
        memberSourceIDs: [SourceID],
        formula: SeriesFormula
    ) {
        self.seriesID = seriesID
        self.metricID = metricID
        self.definitionVersion = definitionVersion
        self.kind = kind
        self.displayName = displayName
        self.memberSourceIDs = memberSourceIDs
        self.formula = formula
    }
}

public struct TransportReadRequest: Codable, Sendable, Equatable {
    public let requestID: RequestID
    public let generation: UInt64
    public let transportHandles: [String]
    public let requestedPeriodMS: Int

    public init(
        requestID: RequestID,
        generation: UInt64,
        transportHandles: [String],
        requestedPeriodMS: Int
    ) {
        self.requestID = requestID
        self.generation = generation
        self.transportHandles = transportHandles
        self.requestedPeriodMS = requestedPeriodMS
    }
}

public enum TransportReadingOutcome: Codable, Sendable, Equatable {
    case success(valueC: Double, sourceWallUnixNS: Int64?, freshness: Freshness)
    case failure(code: MonitorErrorCode, underlyingCode: String?)
}

public struct TransportReading: Codable, Sendable, Equatable {
    public let transportHandle: String
    public let started: Timestamp
    public let finished: Timestamp
    public let outcome: TransportReadingOutcome

    public init(
        transportHandle: String,
        started: Timestamp,
        finished: Timestamp,
        outcome: TransportReadingOutcome
    ) {
        self.transportHandle = transportHandle
        self.started = started
        self.finished = finished
        self.outcome = outcome
    }
}

public struct TransportReadBatch: Codable, Sendable, Equatable {
    public let requestID: RequestID
    public let generation: UInt64
    public let readings: [TransportReading]

    public init(requestID: RequestID, generation: UInt64, readings: [TransportReading]) {
        self.requestID = requestID
        self.generation = generation
        self.readings = readings
    }
}

public struct ReadRequest: Codable, Sendable, Equatable {
    public let requestID: RequestID
    public let sourceIDs: [SourceID]
    public let requestedPeriodMS: Int

    public init(requestID: RequestID, sourceIDs: [SourceID], requestedPeriodMS: Int) {
        self.requestID = requestID
        self.sourceIDs = sourceIDs
        self.requestedPeriodMS = requestedPeriodMS
    }
}

public enum ReadingOutcome: Codable, Sendable, Equatable {
    case success(valueC: Double, sourceWallUnixNS: Int64?, freshness: Freshness)
    case failure(MonitorFailure)
}

public struct Reading: Codable, Sendable, Equatable {
    public let sourceID: SourceID
    public let started: Timestamp
    public let finished: Timestamp
    public let outcome: ReadingOutcome

    public init(
        sourceID: SourceID,
        started: Timestamp,
        finished: Timestamp,
        outcome: ReadingOutcome
    ) {
        self.sourceID = sourceID
        self.started = started
        self.finished = finished
        self.outcome = outcome
    }
}

public struct ReadBatch: Codable, Sendable, Equatable {
    public let requestID: RequestID
    public let generation: UInt64
    public let readings: [Reading]

    public init(requestID: RequestID, generation: UInt64, readings: [Reading]) {
        self.requestID = requestID
        self.generation = generation
        self.readings = readings
    }
}

public struct Sample: Codable, Sendable, Equatable {
    public let sampleID: String
    public let seriesID: SeriesID
    public let segment: Int64
    public let timestamp: Timestamp
    public let periodMS: Int
    public let valueC: Double
    public let freshness: Freshness
    public let sourceWallUnixNS: Int64?
    public let memberSampleIDs: [String]

    public init(
        sampleID: String,
        seriesID: SeriesID,
        segment: Int64,
        timestamp: Timestamp,
        periodMS: Int,
        valueC: Double,
        freshness: Freshness,
        sourceWallUnixNS: Int64?,
        memberSampleIDs: [String]
    ) {
        self.sampleID = sampleID
        self.seriesID = seriesID
        self.segment = segment
        self.timestamp = timestamp
        self.periodMS = periodMS
        self.valueC = valueC
        self.freshness = freshness
        self.sourceWallUnixNS = sourceWallUnixNS
        self.memberSampleIDs = memberSampleIDs
    }
}

public struct EMAValue: Codable, Sendable, Equatable {
    public let sampleID: String
    public let seriesID: SeriesID
    public let segment: Int64
    public let timestamp: Timestamp
    public let valueC: Double

    public init(
        sampleID: String,
        seriesID: SeriesID,
        segment: Int64,
        timestamp: Timestamp,
        valueC: Double
    ) {
        self.sampleID = sampleID
        self.seriesID = seriesID
        self.segment = segment
        self.timestamp = timestamp
        self.valueC = valueC
    }
}

public struct Bucket: Codable, Sendable, Equatable {
    public let seriesID: SeriesID
    public let segment: Int64
    public let widthSeconds: Int
    public let startElapsedNS: Int64
    public let endElapsedNS: Int64
    public let minC: Double
    public let maxC: Double
    public let sumC: Double
    public let count: Int64
    public let latestC: Double
    public let latestElapsedNS: Int64
    public let latestSampleID: String
    public let isPartial: Bool
    public let coverageNS: Int64

    public init(
        seriesID: SeriesID,
        segment: Int64,
        widthSeconds: Int,
        startElapsedNS: Int64,
        endElapsedNS: Int64,
        minC: Double,
        maxC: Double,
        sumC: Double,
        count: Int64,
        latestC: Double,
        latestElapsedNS: Int64,
        latestSampleID: String,
        isPartial: Bool,
        coverageNS: Int64
    ) {
        self.seriesID = seriesID
        self.segment = segment
        self.widthSeconds = widthSeconds
        self.startElapsedNS = startElapsedNS
        self.endElapsedNS = endElapsedNS
        self.minC = minC
        self.maxC = maxC
        self.sumC = sumC
        self.count = count
        self.latestC = latestC
        self.latestElapsedNS = latestElapsedNS
        self.latestSampleID = latestSampleID
        self.isPartial = isPartial
        self.coverageNS = coverageNS
    }
}

public struct TrendValue: Codable, Sendable, Equatable {
    public let seriesID: SeriesID
    public let segment: Int64
    public let at: Timestamp
    public let slopeCPerSecond: Double?
    public let direction: TrendDirection
    public let pointCount: Int

    public init(
        seriesID: SeriesID,
        segment: Int64,
        at: Timestamp,
        slopeCPerSecond: Double?,
        direction: TrendDirection,
        pointCount: Int
    ) {
        self.seriesID = seriesID
        self.segment = segment
        self.at = at
        self.slopeCPerSecond = slopeCPerSecond
        self.direction = direction
        self.pointCount = pointCount
    }
}

public struct Gap: Codable, Sendable, Equatable {
    public let gapID: GapID
    public let seriesID: SeriesID
    public let startedElapsedNS: Int64
    public let endedElapsedNS: Int64?
    public let reason: GapReason

    public init(
        gapID: GapID,
        seriesID: SeriesID,
        startedElapsedNS: Int64,
        endedElapsedNS: Int64?,
        reason: GapReason
    ) {
        self.gapID = gapID
        self.seriesID = seriesID
        self.startedElapsedNS = startedElapsedNS
        self.endedElapsedNS = endedElapsedNS
        self.reason = reason
    }
}

public struct Segment: Codable, Sendable, Equatable {
    public let seriesID: SeriesID
    public let number: Int64
    public let started: Timestamp
    public let reason: SegmentReason

    public init(seriesID: SeriesID, number: Int64, started: Timestamp, reason: SegmentReason) {
        self.seriesID = seriesID
        self.number = number
        self.started = started
        self.reason = reason
    }
}

public struct PersistenceBatch: Codable, Sendable, Equatable {
    public let batchID: BatchID
    public let sources: [QualifiedSource]
    public let definitions: [SeriesDefinition]
    public let segments: [Segment]
    public let raw: [Sample]
    public let ema: [EMAValue]
    public let buckets: [Bucket]
    public let trends: [TrendValue]
    public let gaps: [Gap]

    public init(
        batchID: BatchID,
        sources: [QualifiedSource],
        definitions: [SeriesDefinition],
        segments: [Segment],
        raw: [Sample],
        ema: [EMAValue],
        buckets: [Bucket],
        trends: [TrendValue],
        gaps: [Gap]
    ) {
        self.batchID = batchID
        self.sources = sources
        self.definitions = definitions
        self.segments = segments
        self.raw = raw
        self.ema = ema
        self.buckets = buckets
        self.trends = trends
        self.gaps = gaps
    }
}

public enum PersistenceOwner: Codable, Sendable, Equatable {
    case request(RequestID)
    case gap(GapID)
    case watermark(WatermarkEventID)
}

public struct PersistenceLease: Sendable, Equatable {
    let reservationID: UUID
    public let owner: PersistenceOwner
    public let generation: UInt64
    public let maxRecords: Int
    public let maxBytes: Int

    init(
        reservationID: UUID,
        owner: PersistenceOwner,
        generation: UInt64,
        maxRecords: Int,
        maxBytes: Int
    ) {
        self.reservationID = reservationID
        self.owner = owner
        self.generation = generation
        self.maxRecords = maxRecords
        self.maxBytes = maxBytes
    }
}

public struct ProcessingReceipt: Codable, Sendable, Equatable {
    public let batchID: BatchID
    public let acceptedRecords: Int
    public let snapshotGeneration: UInt64

    public init(batchID: BatchID, acceptedRecords: Int, snapshotGeneration: UInt64) {
        self.batchID = batchID
        self.acceptedRecords = acceptedRecords
        self.snapshotGeneration = snapshotGeneration
    }
}

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

public struct MonitorFailure: Error, Codable, Sendable, Equatable {
    public let code: MonitorErrorCode
    public let severity: Severity
    public let component: String
    public let operation: String
    public let retryCount: Int
    public let sourceID: SourceID?
    public let underlyingCode: String?

    public init(
        code: MonitorErrorCode,
        severity: Severity,
        component: String,
        operation: String,
        retryCount: Int,
        sourceID: SourceID?,
        underlyingCode: String?
    ) {
        self.code = code
        self.severity = severity
        self.component = component
        self.operation = operation
        self.retryCount = retryCount
        self.sourceID = sourceID
        self.underlyingCode = underlyingCode
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

protocol SensorTransport: Sendable {
    func discoverRaw() async throws -> DiscoveredCatalog
    func readRaw(_ request: TransportReadRequest) async throws -> TransportReadBatch
    func close() async
}

public protocol SourceRegistry: Sendable {
    func qualify(_ catalog: DiscoveredCatalog) throws -> QualifiedSourceCatalog
}

public protocol SensorClient: Sendable {
    func discover() async throws -> QualifiedSourceCatalog
    func read(_ request: ReadRequest) async throws -> ReadBatch
    func close() async
}

public protocol PersistenceReservationCapability: Sendable {
    func reserve(
        owner: PersistenceOwner,
        generation: UInt64,
        maxRecords: Int,
        maxBytes: Int
    ) async throws -> PersistenceLease
    func cancel(_ lease: PersistenceLease) async
}

public protocol PersistenceCommitCapability: Sendable {
    func commit(
        _ batch: PersistenceBatch,
        using lease: PersistenceLease
    ) async throws -> ProcessingReceipt
}

public protocol SessionStoreCapability: Sendable {
    func open(_ session: SessionMetadata) async throws
    func query(_ request: HistoryRequest) async throws -> HistoryResult
    func prune(nowElapsedNS: Int64) async throws
    func closeAndDeleteSession() async throws
}

public protocol SessionPersistence:
    PersistenceReservationCapability,
    PersistenceCommitCapability,
    SessionStoreCapability {}

public protocol ProcessingEngine: Sendable {
    func accept(_ batch: ReadBatch, lease: PersistenceLease) async throws -> ProcessingReceipt
    func advance(to timestamp: Timestamp, lease: PersistenceLease) async throws -> ProcessingReceipt
    func markGap(_ gap: Gap, lease: PersistenceLease) async throws -> ProcessingReceipt
    func snapshot(at timestamp: Timestamp) async -> Snapshot
    func realtime(_ request: HistoryRequest) async -> HistoryResult
}

public protocol MonitorController: Sendable {
    func start() async throws
    func setCPUPeriod(milliseconds: Int) async throws
    func snapshots() async -> AsyncStream<Snapshot>
    func history(_ request: HistoryRequest) async throws -> HistoryResult
    func stop() async
}
