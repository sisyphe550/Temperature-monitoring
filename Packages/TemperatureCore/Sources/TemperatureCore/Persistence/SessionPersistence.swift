import CSQLite
import Foundation

final class QueryCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.withLock { cancelled } }

    func cancel() {
        lock.withLock { cancelled = true }
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
    typealias BatchCommitOperation = @Sendable (
        SQLiteStore, PersistenceBatch, SessionID, UInt64
    ) throws -> (ProcessingReceipt, inserted: Bool)

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
    private var operationInFlight = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []
    private var closing = false
    private var capacityPaused = false
    private var batchCommitOperation: BatchCommitOperation = { store, batch, sessionID, generation in
        try store.commitBatch(batch, sessionID: sessionID, snapshotGeneration: generation)
    }

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
        retentionPolicy: RetentionPolicy? = nil,
        batchCommitOperation: @escaping BatchCommitOperation = { store, batch, sessionID, generation in
            try store.commitBatch(batch, sessionID: sessionID, snapshotGeneration: generation)
        }
    ) {
        self.databaseURL = databaseURL
        self.configuration = configuration
        self.retentionPolicy = retentionPolicy
        self.batchCommitOperation = batchCommitOperation
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
        await acquireOperation()
        defer { releaseOperation() }
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
            snapshotGeneration = 0
            closing = false
            capacityPaused = false
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
        guard !capacityPaused else {
            throw Self.failure(code: .databaseBackpressure, operation: "reserve", underlyingCode: "capacity_soft_limit")
        }
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
        guard let reservation = queue?.reservations[lease.reservationID],
              reservation.owner == lease.owner, reservation.generation == lease.generation,
              reservation.maxRecords == lease.maxRecords, reservation.maxBytes == lease.maxBytes else {
            return
        }
        try? queue?.cancelReservation(id: lease.reservationID)
    }

    public func commit(
        _ batch: PersistenceBatch,
        using lease: PersistenceLease
    ) async throws -> ProcessingReceipt {
        // Admit before waiting: close drains every write admitted before it.
        try ensureQueueReady(operation: "commit")
        let admittedAt = ContinuousClock.now
        let admittedWallTime = Date()
        await acquireOperation()
        defer { releaseOperation() }
        guard let store, let session = openedSession, queue != nil else {
            throw Self.failure(code: .databaseInit, operation: "commit", underlyingCode: "session_not_open")
        }

        let recordCount = PersistenceBatchMetrics.logicalRecordCount(batch)
        let byteCount = try PersistenceBatchMetrics.payloadBytes(batch)
        do {
            try queue?.validateReservation(
                id: lease.reservationID, owner: lease.owner, generation: lease.generation,
                recordCount: recordCount, byteCount: byteCount
            )
            guard let reservation = queue?.reservations[lease.reservationID],
                  reservation.maxRecords == lease.maxRecords, reservation.maxBytes == lease.maxBytes else {
                throw BoundedQueueError.ownerMismatch
            }
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
            throw Self.failure(code: .databaseBackpressure, operation: "commit", underlyingCode: "writer_paused")
        }
        try queue?.consumeReservation(
            id: lease.reservationID, owner: lease.owner, generation: lease.generation,
            batch: batch, recordCount: recordCount, byteCount: byteCount, now: admittedWallTime,
            enqueuedContinuouslyAt: admittedAt
        )
        return try await flushUntil(batchID: batch.batchID, store: store, sessionID: session.sessionID)
    }

    public func query(_ request: HistoryRequest) async throws -> HistoryResult {
        try ensureQueueReady(operation: "query")
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
        try ensureQueueReady(operation: "prune")
        await acquireOperation()
        defer { releaseOperation() }
        guard let store else {
            throw Self.failure(code: .databaseInit, operation: "prune", underlyingCode: "session_not_open")
        }
        currentQueryToken?.cancel()
        let policy = try resolvedRetentionPolicy()
        let waits = try resolvedConfiguration().databaseRetryMS
        var retryCount = 0
        while true {
            do {
                capacityPaused = try await runIO {
                    try RetentionEngine(store: store, policy: policy).prune(nowElapsedNS: nowElapsedNS)
                }
                lastPruneElapsedNS = nowElapsedNS
                return
            } catch let error as RetentionError {
                throw Self.mapRetentionError(error, operation: "prune")
            } catch let error as SQLiteStoreError {
                guard Self.isTemporaryStoreError(error), retryCount < waits.count else {
                    throw Self.mapStoreError(error, operation: "prune", retryCount: retryCount)
                }
                try await Task.sleep(for: .milliseconds(waits[retryCount]))
                retryCount += 1
            }
        }
    }

    public func closeAndDeleteSession() async throws {
        closing = true
        currentQueryToken?.cancel()
        await acquireOperation()
        defer { releaseOperation() }
        let url = databaseURL
        if let store {
            await runIO { store.close() }
        }
        store = nil
        openedSession = nil
        queue = nil
        writer = nil
        capacityPaused = false
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

    public func persistenceQueueSnapshot() -> PersistenceQueueSnapshot {
        PersistenceQueueSnapshot(
            totalRecords: queue?.totalRecords ?? 0,
            acceptsNewReservations: !closing && !capacityPaused && (queue?.acceptsNewReservations ?? false)
        )
    }

    func setWriterPausedForTesting(_ paused: Bool) {
        writer?.pausedForTesting = paused
    }

    func appendForTesting(_ batch: PersistenceBatch) async throws -> ProcessingReceipt {
        try ensureQueueReady(operation: "appendForTesting")
        await acquireOperation()
        defer { releaseOperation() }
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
        guard queue != nil, let writer else {
            throw Self.failure(code: .databaseInit, operation: "commit", underlyingCode: "queue_not_ready")
        }
        guard let batches = try queue?.dequeueThrough(batchID: batchID) else {
            throw Self.failure(code: .databaseInit, operation: "commit", underlyingCode: "batch_not_enqueued")
        }
        let records = batches.reduce(into: 0) { $0 += $1.recordCount }
        let bytes = batches.reduce(into: 0) { $0 += $1.byteCount }
        queue?.beginInFlight(records: records, bytes: bytes)
        // Mutate the live queue after every suspension. A local value copy would
        // erase reservations or cancellations made while SQLite is running.
        defer { queue?.finishInFlight(records: records, bytes: bytes) }
        var targetReceipt: ProcessingReceipt?
        for item in batches {
            let receipt = try await commitWithRetry(item, store: store, sessionID: sessionID,
                maxOldestAgeMS: writer.maxOldestAgeMS)
            if item.batch.batchID == batchID { targetReceipt = receipt }
        }
        guard let targetReceipt else {
            throw Self.failure(code: .databaseInit, operation: "commit", underlyingCode: "batch_not_flushed")
        }
        return targetReceipt
    }

    private func commitWithRetry(
        _ item: BoundedQueue.QueuedBatch,
        store: SQLiteStore,
        sessionID: SessionID,
        maxOldestAgeMS: Int
    ) async throws -> ProcessingReceipt {
        let waits = try resolvedConfiguration().databaseRetryMS
        let nextGeneration = snapshotGeneration + 1
        let operation = batchCommitOperation
        var existedBeforeAttempt: Bool?
        var retryCount = 0
        while true {
            let age = item.enqueuedContinuouslyAt.duration(to: ContinuousClock.now)
            guard age <= .milliseconds(maxOldestAgeMS) else {
                throw Self.failure(code: .databaseBackpressure, operation: "commit",
                    underlyingCode: "oldest_age_exceeded", retryCount: retryCount)
            }
            do {
                if existedBeforeAttempt == nil {
                    existedBeforeAttempt = try await runIO {
                        try store.queryExists(sql: "SELECT 1 FROM committed_batches WHERE batch_id = ? LIMIT 1",
                            bindings: [.text(item.batch.batchID.rawValue)])
                    }
                }
                // The value, BatchID and generation remain identical through
                // retries, including a lost acknowledgement after COMMIT.
                let (receipt, inserted) = try await runIO {
                    try operation(store, item.batch, sessionID, nextGeneration)
                }
                if inserted || existedBeforeAttempt == false { snapshotGeneration = nextGeneration }
                return ProcessingReceipt(batchID: receipt.batchID, acceptedRecords: receipt.acceptedRecords,
                    snapshotGeneration: snapshotGeneration)
            } catch let error as SQLiteStoreError {
                guard Self.isTemporaryStoreError(error), retryCount < waits.count else {
                    throw Self.mapStoreError(error, operation: "commit", retryCount: retryCount)
                }
                try await Task.sleep(for: .milliseconds(waits[retryCount]))
                retryCount += 1
            }
        }
    }

    private func acquireOperation() async {
        if !operationInFlight {
            operationInFlight = true
            return
        }
        await withCheckedContinuation { operationWaiters.append($0) }
    }

    private func releaseOperation() {
        if operationWaiters.isEmpty {
            operationInFlight = false
        } else {
            operationWaiters.removeFirst().resume()
        }
    }

    private func ensureQueueReady(operation: String) throws {
        guard !closing, store != nil, queue != nil, writer != nil else {
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
        case .boundaryBudgetExceeded:
            return failure(code: .databaseRead, operation: operation, underlyingCode: "boundary_budget_exceeded")
        case .cancelled, .deadlineExceeded:
            return failure(code: .databaseRead, operation: operation, underlyingCode: "cancelled")
        }
    }

    private static func isTemporaryStoreError(_ error: SQLiteStoreError) -> Bool {
        switch error {
        case .execFailed(let code, _), .prepareFailed(let code, _), .stepFailed(let code, _):
            return [SQLITE_BUSY, SQLITE_LOCKED, SQLITE_IOERR].contains(code & 0xff)
        default:
            return false
        }
    }

    private static func mapStoreError(
        _ error: SQLiteStoreError,
        operation: String,
        retryCount: Int = 0
    ) -> MonitorFailure {
        let code: MonitorErrorCode
        let detail: String
        switch error {
        case .openFailed(_, let message):
            code = .databaseOpen; detail = message
        case .quickCheckFailed(let result):
            code = .databaseCorrupt; detail = result
        case .schemaMismatch(let message):
            code = .databaseSchema; detail = message
        case .integrityConflict(let message):
            code = .databaseIntegrity; detail = message
        case .execFailed(let sqliteCode, let message), .prepareFailed(let sqliteCode, let message),
             .stepFailed(let sqliteCode, let message):
            detail = message
            switch sqliteCode & 0xff {
            case SQLITE_FULL: code = .databaseCapacity
            case SQLITE_CORRUPT, SQLITE_NOTADB: code = .databaseCorrupt
            case SQLITE_SCHEMA: code = .databaseSchema
            case SQLITE_CONSTRAINT: code = .databaseIntegrity
            default:
                switch operation {
                case "commit", "appendForTesting": code = .databaseWrite
                case "prune": code = .databaseClean
                case "query", "rows": code = .databaseRead
                default: code = .databaseInit
                }
            }
        case .closed:
            code = .databaseInit; detail = "closed"
        }
        return failure(code: code, operation: operation, underlyingCode: detail, retryCount: retryCount)
    }

    private static func failure(
        code: MonitorErrorCode,
        operation: String,
        underlyingCode: String,
        retryCount: Int = 0
    ) -> MonitorFailure {
        MonitorFailure(
            code: code,
            severity: .fatal,
            component: "SessionPersistence",
            operation: operation,
            retryCount: retryCount,
            sourceID: nil,
            underlyingCode: underlyingCode
        )
    }
}
