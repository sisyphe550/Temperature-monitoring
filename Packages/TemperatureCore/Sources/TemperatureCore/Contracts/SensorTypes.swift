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
    public let requestedPeriodMS: Int
    public let readings: [Reading]

    public init(
        requestID: RequestID,
        generation: UInt64,
        requestedPeriodMS: Int,
        readings: [Reading]
    ) {
        self.requestID = requestID
        self.generation = generation
        self.requestedPeriodMS = requestedPeriodMS
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

public protocol SensorTransport: Sendable {
    func discoverRaw() async throws -> DiscoveredCatalog
    func readRaw(_ request: TransportReadRequest) async throws -> TransportReadBatch
    func close() async
}

public protocol SensorConnectionGeneration: SensorTransport {
    func currentConnectionGeneration() async -> UInt64
}

public protocol SourceRegistry: Sendable {
    func qualify(_ catalog: DiscoveredCatalog) throws -> QualifiedSourceCatalog
}

public protocol SensorClient: Sendable {
    func discover() async throws -> QualifiedSourceCatalog
    func read(_ request: ReadRequest) async throws -> ReadBatch
    func close() async
}
