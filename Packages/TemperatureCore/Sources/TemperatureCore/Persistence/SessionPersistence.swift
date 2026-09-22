import Foundation

final class QueryCancellationToken: @unchecked Sendable {
    private(set) var isCancelled = false

    func cancel() {
        isCancelled = true
    }
}

public actor SessionPersistenceActor: SessionStoreCapability {
    private let databaseURL: URL
    private let ioQueue = DispatchQueue(label: "com.temperaturemonitor.session-persistence.io")
    private var store: SQLiteStore?
    private var openedSession: SessionMetadata?
    private var snapshotGeneration: UInt64 = 0
    private var currentQueryToken: QueryCancellationToken?
    private var retentionPolicy: RetentionPolicy?
    private var lastPruneElapsedNS: Int64?

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    init(databaseURL: URL, retentionPolicy: RetentionPolicy) {
        self.databaseURL = databaseURL
        self.retentionPolicy = retentionPolicy
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
            let store = try await runIO {
                try Self.openStore(at: url, session: session)
            }
            self.store = store
            openedSession = session
        } catch let error as SQLiteStoreError {
            throw Self.mapStoreError(error, operation: "open")
        }
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
        try await runIO {
            try Self.deleteDatabaseFiles(at: url)
        }
    }

    var openedSessionMetadata: SessionMetadata? {
        openedSession
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

    private func resolvedRetentionPolicy() throws -> RetentionPolicy {
        if let retentionPolicy {
            return retentionPolicy
        }
        let policy = RetentionPolicy(configuration: try Configuration.bundledDefaults())
        retentionPolicy = policy
        return policy
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
