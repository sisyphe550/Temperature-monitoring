// Design contract only. Not the production implementation.
// Copy into Packages/TemperatureCore and split by the file map in docs/08.
import Foundation

public enum SensorKind: String, Codable, Sendable { case cpuMain, cpuZone, ssd, battery }
public enum ProviderKind: String, Codable, Sendable { case smc, hid, nvme, iops }
public enum EvidenceLevel: String, Codable, Sendable { case referenceClassified, targetQualified, unknown }
public enum Capability: String, Codable, Sendable { case available, unsupported, permissionDenied, mappingUnknown, failed }
public enum Freshness: String, Codable, Sendable { case unknown, sourceTimestamp }
public enum GapReason: String, Codable, Sendable { case readFailure, sleep, overload, sourceChange, clockChange, timeout }
public enum TrendDirection: String, Codable, Sendable { case rising, falling, stable, insufficient }
public enum Severity: String, Codable, Sendable { case capability, degraded, fatal }
public enum HistoryRange: Int64, Codable, Sendable { case fiveMinutes = 300, oneHour = 3600, oneDay = 86400, threeDays = 259200 }
public enum HistoryLayer: String, Codable, Sendable { case ema, oneSecond, tenSeconds, oneMinute }

public struct Timestamp: Codable, Sendable, Equatable {
    public let elapsedNS: Int64 // System continuous clock duration since parent session start.
    public let wallUnixNS: Int64 // Actual Date at observation; never used for TTL/dt.


    public init(elapsedNS: Int64, wallUnixNS: Int64) {
        self.elapsedNS = elapsedNS
        self.wallUnixNS = wallUnixNS
    }
}
public struct SessionMetadata: Codable, Sendable, Equatable {
    public let sessionID: String
    public let startedWallUnixNS: Int64
    public let model: String
    public let osBuild: String
    public let appVersion: String

    public init(sessionID: String, startedWallUnixNS: Int64, model: String, osBuild: String, appVersion: String) {
        self.sessionID = sessionID
        self.startedWallUnixNS = startedWallUnixNS
        self.model = model
        self.osBuild = osBuild
        self.appVersion = appVersion
    }
}
public struct SourceDescriptor: Codable, Sendable, Equatable {
    public let sourceID: String // UUID for this connection generation; not a core ID.
    public let provider: ProviderKind
    public let rawKey: String
    public let registryID: String?
    public let connectionGeneration: UInt64
    public let kind: SensorKind
    public let encoding: String
    public let unitEvidence: String
    public let evidence: EvidenceLevel
    public let mappingVersion: String
    public let capability: Capability


    public init(sourceID: String, provider: ProviderKind, rawKey: String, registryID: String?, connectionGeneration: UInt64, kind: SensorKind, encoding: String, unitEvidence: String, evidence: EvidenceLevel, mappingVersion: String, capability: Capability) {
        self.sourceID = sourceID
        self.provider = provider
        self.rawKey = rawKey
        self.registryID = registryID
        self.connectionGeneration = connectionGeneration
        self.kind = kind
        self.encoding = encoding
        self.unitEvidence = unitEvidence
        self.evidence = evidence
        self.mappingVersion = mappingVersion
        self.capability = capability
    }
}
public struct SeriesDefinition: Codable, Sendable, Equatable {
    public let seriesID: String // Source instance or derived-definition UUID.
    public let metricID: String // Stable visible role, e.g. cpu.zone.max.
    public let definitionVersion: Int
    public let kind: SensorKind
    public let displayName: String
    public let memberSourceIDs: [String]
    public let formula: String // identity or max in v1.


    public init(seriesID: String, metricID: String, definitionVersion: Int, kind: SensorKind, displayName: String, memberSourceIDs: [String], formula: String) {
        self.seriesID = seriesID
        self.metricID = metricID
        self.definitionVersion = definitionVersion
        self.kind = kind
        self.displayName = displayName
        self.memberSourceIDs = memberSourceIDs
        self.formula = formula
    }
}
public struct ReadRequest: Codable, Sendable {
    public let requestID: String
    public let sourceIDs: [String]
    public let requestedPeriodMS: Int


    public init(requestID: String, sourceIDs: [String], requestedPeriodMS: Int) {
        self.requestID = requestID
        self.sourceIDs = sourceIDs
        self.requestedPeriodMS = requestedPeriodMS
    }
}
public struct Reading: Codable, Sendable {
    public let sourceID: String
    public let valueC: Double?
    public let started: Timestamp
    public let finished: Timestamp
    public let sourceWallUnixNS: Int64?
    public let freshness: Freshness
    public let failure: MonitorFailure?


    public init(sourceID: String, valueC: Double?, started: Timestamp, finished: Timestamp, sourceWallUnixNS: Int64?, freshness: Freshness, failure: MonitorFailure?) {
        self.sourceID = sourceID
        self.valueC = valueC
        self.started = started
        self.finished = finished
        self.sourceWallUnixNS = sourceWallUnixNS
        self.freshness = freshness
        self.failure = failure
    }
}
public struct ReadBatch: Codable, Sendable {
    public let requestID: String
    public let generation: UInt64
    public let readings: [Reading]


    public init(requestID: String, generation: UInt64, readings: [Reading]) {
        self.requestID = requestID
        self.generation = generation
        self.readings = readings
    }
}
public struct Sample: Codable, Sendable, Equatable {
    public let sampleID: String // session UUID + monotonically increasing sequence.
    public let seriesID: String
    public let segment: Int64
    public let timestamp: Timestamp
    public let periodMS: Int
    public let valueC: Double
    public let freshness: Freshness
    public let sourceWallUnixNS: Int64?
    public let memberSampleIDs: [String] // Empty for physical source; provenance for derived.


    public init(sampleID: String, seriesID: String, segment: Int64, timestamp: Timestamp, periodMS: Int, valueC: Double, freshness: Freshness, sourceWallUnixNS: Int64?, memberSampleIDs: [String]) {
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
    public let seriesID: String
    public let segment: Int64
    public let timestamp: Timestamp
    public let valueC: Double


    public init(sampleID: String, seriesID: String, segment: Int64, timestamp: Timestamp, valueC: Double) {
        self.sampleID = sampleID
        self.seriesID = seriesID
        self.segment = segment
        self.timestamp = timestamp
        self.valueC = valueC
    }
}
public struct Bucket: Codable, Sendable, Equatable {
    public let seriesID: String
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


    public init(seriesID: String, segment: Int64, widthSeconds: Int, startElapsedNS: Int64, endElapsedNS: Int64, minC: Double, maxC: Double, sumC: Double, count: Int64, latestC: Double, latestElapsedNS: Int64, latestSampleID: String, isPartial: Bool, coverageNS: Int64) {
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
    public let seriesID: String
    public let segment: Int64
    public let at: Timestamp
    public let slopeCPerSecond: Double?
    public let direction: TrendDirection
    public let pointCount: Int


    public init(seriesID: String, segment: Int64, at: Timestamp, slopeCPerSecond: Double?, direction: TrendDirection, pointCount: Int) {
        self.seriesID = seriesID
        self.segment = segment
        self.at = at
        self.slopeCPerSecond = slopeCPerSecond
        self.direction = direction
        self.pointCount = pointCount
    }
}
public struct Gap: Codable, Sendable, Equatable {
    public let gapID: String
    public let seriesID: String
    public let startedElapsedNS: Int64
    public let endedElapsedNS: Int64?
    public let reason: GapReason


    public init(gapID: String, seriesID: String, startedElapsedNS: Int64, endedElapsedNS: Int64?, reason: GapReason) {
        self.gapID = gapID
        self.seriesID = seriesID
        self.startedElapsedNS = startedElapsedNS
        self.endedElapsedNS = endedElapsedNS
        self.reason = reason
    }
}
public struct Segment: Codable, Sendable, Equatable {
    public let seriesID: String
    public let number: Int64
    public let started: Timestamp
    public let reason: String


    public init(seriesID: String, number: Int64, started: Timestamp, reason: String) {
        self.seriesID = seriesID
        self.number = number
        self.started = started
        self.reason = reason
    }
}
public struct PersistenceBatch: Codable, Sendable {
    public let batchID: String
    public let sources: [SourceDescriptor]
    public let definitions: [SeriesDefinition]
    public let segments: [Segment]
    public let raw: [Sample]
    public let ema: [EMAValue]
    public let buckets: [Bucket]
    public let trends: [TrendValue]
    public let gaps: [Gap]


    public init(batchID: String, sources: [SourceDescriptor], definitions: [SeriesDefinition], segments: [Segment], raw: [Sample], ema: [EMAValue], buckets: [Bucket], trends: [TrendValue], gaps: [Gap]) {
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
public struct QueueReservation: Codable, Sendable, Equatable {
    public let reservationID: String
    public let ownerID: String // requestID, watermark event ID, or gapID.
    public let generation: UInt64
    public let maxRecords: Int
    public let maxBytes: Int

    public init(reservationID: String, ownerID: String, generation: UInt64, maxRecords: Int, maxBytes: Int) {
        self.reservationID = reservationID
        self.ownerID = ownerID
        self.generation = generation
        self.maxRecords = maxRecords
        self.maxBytes = maxBytes
    }
}
public struct LatestValue: Codable, Sendable {
    public let definition: SeriesDefinition
    public let ema: EMAValue?
    public let capability: Capability
    public let cached: Bool
    public let stale: Bool
    public let reason: String?


    public init(definition: SeriesDefinition, ema: EMAValue?, capability: Capability, cached: Bool, stale: Bool, reason: String?) {
        self.definition = definition
        self.ema = ema
        self.capability = capability
        self.cached = cached
        self.stale = stale
        self.reason = reason
    }
}
public struct Snapshot: Sendable {
    public let asOf: Timestamp
    public let values: [LatestValue]
    public let gapIDs: [String]
    public let cpuPeriodMS: Int


    public init(asOf: Timestamp, values: [LatestValue], gapIDs: [String], cpuPeriodMS: Int) {
        self.asOf = asOf
        self.values = values
        self.gapIDs = gapIDs
        self.cpuPeriodMS = cpuPeriodMS
    }
}
public struct HistoryRequest: Sendable {
    public let seriesIDs: [String]
    public let range: HistoryRange
    public let asOfElapsedNS: Int64
    public let pointLimit: Int


    public init(seriesIDs: [String], range: HistoryRange, asOfElapsedNS: Int64, pointLimit: Int) {
        self.seriesIDs = seriesIDs
        self.range = range
        self.asOfElapsedNS = asOfElapsedNS
        self.pointLimit = pointLimit
    }
}
public struct HistoryPoint: Sendable {
    public let seriesID: String
    public let segment: Int64
    public let elapsedNS: Int64
    public let wallUnixNS: Int64?
    public let valueC: Double
    public let minC: Double?
    public let maxC: Double?
    public let count: Int64


    public init(seriesID: String, segment: Int64, elapsedNS: Int64, wallUnixNS: Int64?, valueC: Double, minC: Double?, maxC: Double?, count: Int64) {
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
public struct HistoryResult: Sendable {
    public let layer: HistoryLayer
    public let points: [HistoryPoint]
    public let gaps: [Gap]
    public let availableFromElapsedNS: Int64?
    public let persistedThroughElapsedNS: Int64?


    public init(layer: HistoryLayer, points: [HistoryPoint], gaps: [Gap], availableFromElapsedNS: Int64?, persistedThroughElapsedNS: Int64?) {
        self.layer = layer
        self.points = points
        self.gaps = gaps
        self.availableFromElapsedNS = availableFromElapsedNS
        self.persistedThroughElapsedNS = persistedThroughElapsedNS
    }
}
public struct MonitorFailure: Error, Codable, Sendable {
    public let code: String
    public let severity: Severity
    public let component: String
    public let operation: String
    public let retryCount: Int
    public let sourceID: String?
    public let underlyingCode: String?


    public init(code: String, severity: Severity, component: String, operation: String, retryCount: Int, sourceID: String?, underlyingCode: String?) {
        self.code = code
        self.severity = severity
        self.component = component
        self.operation = operation
        self.retryCount = retryCount
        self.sourceID = sourceID
        self.underlyingCode = underlyingCode
    }
}
public protocol MonitorClock: Sendable {
    func now() -> Timestamp
    func sleep(untilElapsedNS: Int64) async throws
}
public protocol SensorClient: Sendable {
    func discover() async throws -> [SourceDescriptor]
    func read(_ request: ReadRequest) async throws -> ReadBatch
    func close() async
}
public protocol ProcessingEngine: Sendable {
    func accept(_ batch: ReadBatch, reservation: QueueReservation) async throws -> PersistenceBatch
    func advance(to timestamp: Timestamp, reservation: QueueReservation) async throws -> PersistenceBatch
    func markGap(_ gap: Gap, reservation: QueueReservation) async throws -> PersistenceBatch
    func snapshot(at timestamp: Timestamp) async -> Snapshot
    func realtime(_ request: HistoryRequest) async -> HistoryResult
}
public protocol PersistenceQueue: Sendable {
    func reserve(ownerID: String, generation: UInt64, maxRecords: Int, maxBytes: Int) async throws -> QueueReservation
    func enqueue(_ batch: PersistenceBatch, using reservation: QueueReservation) async throws
    func cancel(_ reservation: QueueReservation) async
}
public protocol SampleStore: Sendable {
    func open(_ session: SessionMetadata) async throws
    func register(_ sources: [SourceDescriptor], definitions: [SeriesDefinition]) async throws
    func append(_ batch: PersistenceBatch) async throws
    func query(_ request: HistoryRequest) async throws -> HistoryResult
    func prune(nowElapsedNS: Int64) async throws
    func closeAndDeleteSession() async throws
}
public protocol MonitorController: Sendable {
    func start() async throws
    func setCPUPeriod(milliseconds: Int) async throws
    func snapshots() async -> AsyncStream<Snapshot>
    func history(_ request: HistoryRequest) async throws -> HistoryResult
    func stop() async
}
