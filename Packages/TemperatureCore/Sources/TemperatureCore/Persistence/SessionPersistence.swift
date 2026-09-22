import Foundation

final class QueryCancellationToken: @unchecked Sendable {
    private(set) var isCancelled = false

    func cancel() {
        isCancelled = true
    }
}

public struct SessionPersistenceReservationCapability: PersistenceReservationCapability {
    private let persistence: SessionPersistenceActor

    init(_ persistence: SessionPersistenceActor) {
        self.persistence = persistence
    }

    public func reserve(
        owner: PersistenceOwner,
        generation: UInt64,
        maxRecords: Int,
        maxBytes: Int
    ) async throws -> PersistenceLease {
        try await persistence.reserve(
            owner: owner,
            generation: generation,
            maxRecords: maxRecords,
            maxBytes: maxBytes
        )
    }

    public func cancel(_ lease: PersistenceLease) async {
        await persistence.cancel(lease)
    }
}

public struct SessionPersistenceCommitCapability: PersistenceCommitCapability {
    private let persistence: SessionPersistenceActor

    init(_ persistence: SessionPersistenceActor) {
        self.persistence = persistence
    }

    public func commit(
        _ batch: PersistenceBatch,
        using lease: PersistenceLease
    ) async throws -> ProcessingReceipt {
        try await persistence.commit(batch, using: lease)
    }
}

public actor SessionPersistenceActor: SessionPersistence {
    private let databaseURL: URL
    private let ioQueue = DispatchQueue(label: "com.temperaturemonitor.session-persistence.io")
    private var store: SQLiteStore?
    private var openedSession: SessionMetadata?
    private var snapshotGeneration: UInt64 = 0
    private var currentQueryToken: QueryCancellationToken?
    private var retentionPolicy: RetentionPolicy?
    private var lastPruneElapsedNS: Int64?
    private var configuration: RuntimeConfiguration?
    private var queue: BoundedQueue?
    private var writer: StorageWriter?

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    init(databaseURL: URL, retentionPolicy: RetentionPolicy) {
        self.databaseURL = databaseURL
        self.retentionPolicy = retentionPolicy
    }

    init(
        databaseURL: URL,
        configuration: RuntimeConfiguration,
        retentionPolicy: RetentionPolicy? = nil
    ) {
        self.databaseURL = databaseURL
        self.configuration = configuration
        self.retentionPolicy = retentionPolicy
        queue = BoundedQueue(configuration: configuration)
        writer = StorageWriter(configuration: configuration)
    }

    public func reservationCapability() -> PersistenceReservationCapability {
        SessionPersistenceReservationCapability(self)
    }

    public func commitCapability() -> PersistenceCommitCapability {
        SessionPersistenceCommitCapability(self)
    }

    public func open(_ session: SessionMetadata) async throws {
        guard store == nil else {
            throw Self.failure(
                code: .databaseInit,
                operation: "open",
                underlyingCode: "already_open"
            )
        }

        let url = databaseURL
        do {
            let runtimeConfiguration = try resolvedConfiguration()
            queue = BoundedQueue(configuration: runtimeConfiguration)
            writer = StorageWriter(configuration: runtimeConfiguration)
            let store = try await runIO {
                try Self.openStore(at: url, session: session)
            }
            self.store = store
            openedSession = session
        } catch let error as SQLiteStoreError {
            throw Self.mapStoreError(error, operation: "open")
        }
    }

    public func reserve(
        owner: PersistenceOwner,
        generation: UInt64,
        maxRecords: Int,
        maxBytes: Int
    ) async throws -> PersistenceLease {
        try ensureQueueReady(operation: "reserve")
        let runtimeConfiguration = try resolvedConfiguration()
        guard maxRecords <= runtimeConfiguration.writerReserveRecordsPerEvent else {
            throw Self.integrityFailure(operation: "reserve", underlyingCode: "reserve_exceeds_event_limit")
        }
        guard maxBytes <= runtimeConfiguration.writerMaxPayloadBytes else {
            throw Self.integrityFailure(operation: "reserve", underlyingCode: "reserve_exceeds_byte_limit")
        }

        let reservationID = UUID()
        do {
            try queue?.registerReservation(
                id: reservationID,
                owner: owner,
                generation: generation,
                reservedRecords: maxRecords,
                reservedBytes: maxBytes
            )
        } catch BoundedQueueError.backpressure {
            throw Self.failure(
                code: .databaseBackpressure,
                operation: "reserve",
                underlyingCode: "backpressure"
            )
        } catch BoundedQueueError.capacityExceeded {
            throw Self.failure(
                code: .databaseBackpressure,
                operation: "reserve",
                underlyingCode: "capacity_exceeded"
            )
        } catch {
            throw Self.integrityFailure(operation: "reserve", underlyingCode: "invalid_capacity")
        }

        return PersistenceLease(
            reservationID: reservationID,
            owner: owner,
            generation: generation,
            maxRecords: maxRecords,
            maxBytes: maxBytes
        )
    }

    public func cancel(_ lease: PersistenceLease) async {
        do {
            try queue?.cancelReservation(id: lease.reservationID)
        } catch {
            return
        }
    }

    public func commit(
        _ batch: PersistenceBatch,
        using lease: PersistenceLease
    ) async throws -> ProcessingReceipt {
        try ensureQueueReady(operation: "commit")
        guard let store, let session = openedSession, var queue else {
            throw Self.failure(
                code: .databaseInit,
                operation: "commit",
                underlyingCode: "session_not_open"
            )
        }

        let recordCount = PersistenceBatchMetrics.logicalRecordCount(batch)
        let byteCount = try PersistenceBatchMetrics.payloadBytes(batch)
        do {
            try queue.validateReservation(
                id: lease.reservationID,
                owner: lease.owner,
                generation: lease.generation,
                recordCount: recordCount,
                byteCount: byteCount
            )
        } catch BoundedQueueError.unknownReservation {
            throw Self.integrityFailure(operation: "commit", underlyingCode: "unknown_reservation")
        } catch BoundedQueueError.reservationNotActive {
            throw Self.integrityFailure(operation: "commit", underlyingCode: "reservation_not_active")
        } catch BoundedQueueError.ownerMismatch {
            throw Self.integrityFailure(operation: "commit", underlyingCode: "owner_or_generation_mismatch")
        } catch BoundedQueueError.capacityExceeded {
            throw Self.integrityFailure(operation: "commit", underlyingCode: "batch_exceeds_lease")
        } catch {
            throw Self.integrityFailure(operation: "commit", underlyingCode: "invalid_commit")
        }

        if writer?.pausedForTesting == true {
            throw Self.failure(
                code: .databaseBackpressure,
                operation: "commit",
                underlyingCode: "writer_paused"
            )
        }

        do {
            try queue.consumeReservation(
                id: lease.reservationID,
                owner: lease.owner,
                generation: lease.generation,
                batch: batch,
                recordCount: recordCount,
                byteCount: byteCount,
                now: Date()
            )
        } catch {
            throw Self.integrityFailure(operation: "commit", underlyingCode: "invalid_commit")
        }
        self.queue = queue

        return try await flushUntil(batchID: batch.batchID, store: store, sessionID: session.sessionID)
    }

    public func query(_ request: HistoryRequest) async throws -> HistoryResult {
        guard let store else {
            throw Self.failure(
                code: .databaseInit,
                operation: "query",
                underlyingCode: "session_not_open"
            )
        }

        currentQueryToken?.cancel()
        let token = QueryCancellationToken()
        currentQueryToken = token

        do {
            let result = try await runIO {
                try HistoryQueryEngine(store: store).execute(request) {
                    token.isCancelled
                }
            }
            if token.isCancelled {
                throw Self.failure(
                    code: .databaseRead,
                    operation: "query",
                    underlyingCode: "superseded"
                )
            }
            return result
        } catch let error as HistoryQueryError {
            if token.isCancelled {
                throw Self.failure(
                    code: .databaseRead,
                    operation: "query",
                    underlyingCode: "superseded"
                )
            }
            throw Self.mapHistoryQueryError(error, operation: "query")
        } catch let error as SQLiteStoreError {
            throw Self.mapStoreError(error, operation: "query")
        }
    }

    public func prune(nowElapsedNS: Int64) async throws {
        guard let store else {
            throw Self.failure(
                code: .databaseInit,
                operation: "prune",
                underlyingCode: "session_not_open"
            )
        }

        do {
            let policy = try resolvedRetentionPolicy()
            try await runIO {
                try RetentionEngine(store: store, policy: policy).prune(nowElapsedNS: nowElapsedNS)
            }
            lastPruneElapsedNS = nowElapsedNS
        } catch let error as RetentionError {
            throw Self.mapRetentionError(error, operation: "prune")
        } catch let error as SQLiteStoreError {
            throw Self.mapStoreError(error, operation: "prune")
        }
    }

    public func closeAndDeleteSession() async throws {
        let url = databaseURL
        if let store {
            await runIO { store.close() }
        }
        store = nil
        openedSession = nil
        queue = nil
        writer = nil
        try await runIO {
            try Self.deleteDatabaseFiles(at: url)
        }
    }

    var openedSessionMetadata: SessionMetadata? {
        openedSession
    }

    var queueRecordCountForTesting: Int {
        queue?.totalRecords ?? 0
    }

    var isBackpressureLatchedForTesting: Bool {
        queue?.backpressureLatched ?? false
    }

    func setWriterPausedForTesting(_ paused: Bool) {
        writer?.pausedForTesting = paused
    }

    func appendForTesting(_ batch: PersistenceBatch) async throws -> ProcessingReceipt {
        guard let store, let session = openedSession else {
            throw Self.failure(
                code: .databaseInit,
                operation: "appendForTesting",
                underlyingCode: "session_not_open"
            )
        }

        let nextGeneration = snapshotGeneration + 1
        do {
            let (receipt, inserted) = try await runIO {
                try store.commitBatch(
                    batch,
                    sessionID: session.sessionID,
                    snapshotGeneration: nextGeneration
                )
            }
            if inserted {
                snapshotGeneration = nextGeneration
                return receipt
            }
            return ProcessingReceipt(
                batchID: receipt.batchID,
                acceptedRecords: receipt.acceptedRecords,
                snapshotGeneration: snapshotGeneration
            )
        } catch let error as SQLiteStoreError {
            throw Self.mapStoreError(error, operation: "appendForTesting")
        }
    }

    func rows(in table: String) async throws -> Int {
        guard let store else {
            throw Self.failure(
                code: .databaseInit,
                operation: "rows",
                underlyingCode: "session_not_open"
            )
        }
        do {
            return try await runIO {
                try store.rowCount(in: table)
            }
        } catch let error as SQLiteStoreError {
            throw Self.mapStoreError(error, operation: "rows")
        }
    }

    private func flushUntil(
        batchID: BatchID,
        store: SQLiteStore,
        sessionID: SessionID
    ) async throws -> ProcessingReceipt {
        guard var queue, let writer else {
            throw Self.failure(
                code: .databaseInit,
                operation: "commit",
                underlyingCode: "queue_not_ready"
            )
        }

        let now = Date()
        if let oldestAgeMS = queue.oldestPendingAgeMS(now: now) {
            try writer.validateOldestAge(oldestAgeMS)
        }

        let batches: [BoundedQueue.QueuedBatch]
        do {
            batches = try queue.dequeueThrough(batchID: batchID)
        } catch BoundedQueueError.unknownBatch {
            throw Self.failure(
                code: .databaseInit,
                operation: "commit",
                underlyingCode: "batch_not_enqueued"
            )
        }

        let inFlightRecords = batches.reduce(into: 0) { $0 += $1.recordCount }
        let inFlightBytes = batches.reduce(into: 0) { $0 += $1.byteCount }
        queue.beginInFlight(records: inFlightRecords, bytes: inFlightBytes)
        self.queue = queue

        var targetReceipt: ProcessingReceipt?
        do {
            for item in batches {
                let nextGeneration = snapshotGeneration + 1
                let (receipt, inserted) = try await runIO {
                    try store.commitBatch(
                        item.batch,
                        sessionID: sessionID,
                        snapshotGeneration: nextGeneration
                    )
                }
                if inserted {
                    snapshotGeneration = nextGeneration
                }
                if item.batch.batchID == batchID {
                    targetReceipt = ProcessingReceipt(
                        batchID: receipt.batchID,
                        acceptedRecords: receipt.acceptedRecords,
                        snapshotGeneration: snapshotGeneration
                    )
                }
            }
        } catch let error as SQLiteStoreError {
            queue.requeueFront(batches)
            queue.finishInFlight(records: inFlightRecords, bytes: inFlightBytes)
            self.queue = queue
            throw Self.mapStoreError(error, operation: "commit")
        }

        queue.finishInFlight(records: inFlightRecords, bytes: inFlightBytes)
        self.queue = queue

        guard let targetReceipt else {
            throw Self.failure(
                code: .databaseInit,
                operation: "commit",
                underlyingCode: "batch_not_flushed"
            )
        }
        return targetReceipt
    }

    private func ensureQueueReady(operation: String) throws {
        guard store != nil, queue != nil, writer != nil else {
            throw Self.failure(
                code: .databaseInit,
                operation: operation,
                underlyingCode: "session_not_open"
            )
        }
    }

    private func runIO<T: Sendable>(
        _ work: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runIO(
        _ work: @escaping @Sendable () -> Void
    ) async {
        await withCheckedContinuation { continuation in
            ioQueue.async {
                work()
                continuation.resume()
            }
        }
    }

    private static func openStore(at databaseURL: URL, session: SessionMetadata) throws -> SQLiteStore {
        let parent = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let store = try SQLiteStore(databaseURL: databaseURL)
        try store.applyBundledSchemaIfNeeded()
        try store.quickCheck()
        try store.insertSession(session)
        return store
    }

    private static func deleteDatabaseFiles(at databaseURL: URL) throws {
        let fm = FileManager.default
        let paths = [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm"),
        ]
        for url in paths where fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    private func resolvedConfiguration() throws -> RuntimeConfiguration {
        if let configuration {
            return configuration
        }
        let loaded = try Configuration.bundledDefaults()
        configuration = loaded
        return loaded
    }

    private func resolvedRetentionPolicy() throws -> RetentionPolicy {
        if let retentionPolicy {
            return retentionPolicy
        }
        let policy = RetentionPolicy(configuration: try resolvedConfiguration())
        retentionPolicy = policy
        return policy
    }

    private static func integrityFailure(operation: String, underlyingCode: String) -> MonitorFailure {
        failure(code: .databaseIntegrity, operation: operation, underlyingCode: underlyingCode)
    }

    private static func mapRetentionError(_ error: RetentionError, operation: String) -> MonitorFailure {
        switch error {
        case .cleanupGraceExceeded:
            return failure(code: .databaseClean, operation: operation, underlyingCode: "grace_exceeded")
        case .capacityExceeded, .walCapacityExceeded:
            return failure(code: .databaseCapacity, operation: operation, underlyingCode: "capacity_exceeded")
        }
    }

    private static func mapHistoryQueryError(_ error: HistoryQueryError, operation: String) -> MonitorFailure {
        switch error {
        case .unsupportedRange:
            return failure(code: .databaseRead, operation: operation, underlyingCode: "unsupported_range")
        case .emptySeries:
            return failure(code: .databaseRead, operation: operation, underlyingCode: "empty_series")
        case .tooManySeries:
            return failure(code: .databaseRead, operation: operation, underlyingCode: "too_many_series")
        case .invalidPointLimit:
            return failure(code: .databaseRead, operation: operation, underlyingCode: "invalid_point_limit")
        case .duplicateSeries:
            return failure(code: .databaseIntegrity, operation: operation, underlyingCode: "duplicate_series")
        case .cancelled, .deadlineExceeded:
            return failure(code: .databaseRead, operation: operation, underlyingCode: "cancelled")
        }
    }

    private static func mapStoreError(_ error: SQLiteStoreError, operation: String) -> MonitorFailure {
        switch error {
        case .openFailed(_, let message):
            return failure(code: .databaseOpen, operation: operation, underlyingCode: message)
        case .quickCheckFailed(let result):
            return failure(code: .databaseCorrupt, operation: operation, underlyingCode: result)
        case .schemaMismatch(let detail):
            return failure(code: .databaseSchema, operation: operation, underlyingCode: detail)
        case .integrityConflict(let detail):
            return failure(code: .databaseIntegrity, operation: operation, underlyingCode: detail)
        case .execFailed(_, let message), .prepareFailed(_, let message), .stepFailed(_, let message):
            return failure(code: .databaseInit, operation: operation, underlyingCode: message)
        case .closed:
            return failure(code: .databaseInit, operation: operation, underlyingCode: "closed")
        }
    }

    private static func failure(
        code: MonitorErrorCode,
        operation: String,
        underlyingCode: String
    ) -> MonitorFailure {
        MonitorFailure(
            code: code,
            severity: .fatal,
            component: "SessionPersistence",
            operation: operation,
            retryCount: 0,
            sourceID: nil,
            underlyingCode: underlyingCode
        )
    }
}
