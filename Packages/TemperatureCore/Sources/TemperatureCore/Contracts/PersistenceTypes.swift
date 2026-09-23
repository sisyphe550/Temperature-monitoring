import Foundation

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

public struct PersistenceQueueSnapshot: Sendable, Equatable {
    public let totalRecords: Int
    public let acceptsNewReservations: Bool
}
