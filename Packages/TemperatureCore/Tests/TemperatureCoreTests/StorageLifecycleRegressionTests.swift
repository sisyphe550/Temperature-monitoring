import CSQLite
import Foundation
import Testing
@testable import TemperatureCore

@Suite(.serialized) struct StorageLifecycleRegressionTests {
    @Test func finalizedReservationMetadataDoesNotGrowWithSessionReads() throws {
        var queue = BoundedQueue(configuration: try Configuration.bundledDefaults())
        for index in 0..<4_000 {
            let id = UUID()
            let owner = PersistenceOwner.request(RequestID(UUID()))
            try queue.registerReservation(id: id, owner: owner, generation: 1, reservedRecords: 1, reservedBytes: 512)
            if index.isMultiple(of: 2) {
                try queue.cancelReservation(id: id)
            } else {
                let batch = storageEmptyBatch()
                try queue.consumeReservation(id: id, owner: owner, generation: 1, batch: batch,
                    recordCount: 0, byteCount: 100, now: Date())
                _ = try queue.dequeueThrough(batchID: batch.batchID)
            }
        }
        #expect(queue.reservations.count == 0)
        #expect(queue.totalRecords == 0)
        #expect(queue.totalBytes == 0)
    }

    @Test func forgedCancellationDoesNotInvalidateTheAuthenticLease() async throws {
        let fixture = try await StorageRegressionFixture.make()
        let lease = try await fixture.reserve()
        let forged = PersistenceLease(reservationID: lease.reservationID, owner: .request(RequestID(UUID())),
            generation: lease.generation, maxRecords: lease.maxRecords, maxBytes: lease.maxBytes)
        await fixture.session.cancel(forged)
        let result = await storageResult { try await fixture.session.commit(storageEmptyBatch(), using: lease) }
        #expect(result.failure == nil)
        await fixture.session.cancel(lease)
        await fixture.session.cancel(lease)
        try await fixture.session.closeAndDeleteSession()
    }

    @Test func temporaryWriteFailureRetriesSameBatchAndPayload() async throws {
        let attempts = StorageAttemptLog()
        let fixture = try await StorageRegressionFixture.make { store, batch, sessionID, generation in
            if try attempts.record(batch) == 1 {
                throw SQLiteStoreError.execFailed(code: SQLITE_BUSY, message: "database is busy")
            }
            return try store.commitBatch(batch, sessionID: sessionID, snapshotGeneration: generation)
        }
        let batch = try Fixtures.persistence(id: BatchID(UUID()), value: 70, ms: 100)
        let lease = try await fixture.reserve()
        let result = await storageResult { try await fixture.session.commit(batch, using: lease) }
        #expect(result.failure == nil)
        #expect(result.receipt?.batchID == batch.batchID)
        #expect(attempts.count == 2)
        #expect(Set(attempts.batchIDs).count == 1)
        #expect(Set(attempts.hashes).count == 1)
        #expect(try await fixture.session.rows(in: "raw_samples") == 1)
        try await fixture.session.closeAndDeleteSession()
    }

    @Test func lostCommitAcknowledgementRetriesWithoutDuplicateSamples() async throws {
        let attempts = StorageAttemptLog()
        let fixture = try await StorageRegressionFixture.make { store, batch, sessionID, generation in
            let ordinal = try attempts.record(batch)
            let receipt = try store.commitBatch(batch, sessionID: sessionID, snapshotGeneration: generation)
            if ordinal == 1 {
                throw SQLiteStoreError.stepFailed(code: SQLITE_IOERR, message: "acknowledgement lost after COMMIT")
            }
            return receipt
        }
        let batch = try Fixtures.persistence(id: BatchID(UUID()), value: 70, ms: 100)
        let lease = try await fixture.reserve()
        let result = await storageResult { try await fixture.session.commit(batch, using: lease) }
        #expect(result.failure == nil)
        #expect(result.receipt?.batchID == batch.batchID)
        #expect(result.receipt?.snapshotGeneration == 1)
        #expect(attempts.count == 2)
        #expect(Set(attempts.hashes).count == 1)
        #expect(try await fixture.session.rows(in: "raw_samples") == 1)
        #expect(try await fixture.session.rows(in: "ema_samples") == 1)
        #expect(try await fixture.session.rows(in: "committed_batches") == 1)
        let duplicate = await storageResult { try await fixture.session.commit(batch, using: lease) }
        #expect(duplicate.failure?.code == .databaseIntegrity)
        try await fixture.session.closeAndDeleteSession()
    }

    @Test func reservationCreatedDuringWriteSurvivesActorReentry() async throws {
        let gate = StorageIOGate()
        let fixture = try await StorageRegressionFixture.make { store, batch, sessionID, generation in
            gate.blockFirstOperation()
            return try store.commitBatch(batch, sessionID: sessionID, snapshotGeneration: generation)
        }
        let firstLease = try await fixture.reserve()
        let firstWrite = Task { await storageResult { try await fixture.session.commit(storageEmptyBatch(), using: firstLease) } }
        try await storageWaitUntil { gate.isBlocked }
        let secondLease = try await fixture.reserve()
        gate.release()
        #expect(await firstWrite.value.failure == nil)
        let secondWrite = await storageResult { try await fixture.session.commit(storageEmptyBatch(), using: secondLease) }
        #expect(secondWrite.failure == nil)
        try await fixture.session.closeAndDeleteSession()
    }

    @Test func writeRetryExhaustionUsesFiveAdditionalAttemptsAndWriteError() async throws {
        let attempts = StorageAttemptLog()
        let fixture = try await StorageRegressionFixture.make { _, batch, _, _ in
            _ = try attempts.record(batch)
            throw SQLiteStoreError.execFailed(code: SQLITE_LOCKED, message: "locked")
        }
        let lease = try await fixture.reserve()
        let result = await storageResult { try await fixture.session.commit(storageEmptyBatch(), using: lease) }
        #expect(attempts.count == 6)
        #expect(result.failure?.code == .databaseWrite)
        #expect(result.failure?.retryCount == 5)
        #expect(Set(attempts.hashes).count == 1)
        #expect(await fixture.session.persistenceQueueSnapshot().totalRecords == 0)
        try await fixture.session.closeAndDeleteSession()
    }

    @Test func integrityConflictIsNotRetried() async throws {
        let attempts = StorageAttemptLog()
        let fixture = try await StorageRegressionFixture.make { _, batch, _, _ in
            _ = try attempts.record(batch)
            throw SQLiteStoreError.integrityConflict(detail: "conflicting payload")
        }
        let lease = try await fixture.reserve()
        let result = await storageResult { try await fixture.session.commit(storageEmptyBatch(), using: lease) }
        #expect(attempts.count == 1)
        #expect(result.failure?.code == .databaseIntegrity)
        try await fixture.session.closeAndDeleteSession()
    }

    @Test func walSoftLimitAttemptsTruncateCheckpoint() async throws {
        let defaults = try Configuration.bundledDefaults()
        let policy = RetentionPolicy(retention: defaults.retentionSeconds, graceSeconds: defaults.retentionGraceSeconds,
            dbSoftBytes: defaults.dbSoftBytes, dbHardBytes: defaults.dbHardBytes,
            walSoftBytes: 1, walHardBytes: defaults.walHardBytes)
        let fixture = try await StorageRegressionFixture.make(retentionPolicy: policy)
        let lease = try await fixture.reserve()
        _ = try await fixture.session.commit(storageEmptyBatch(), using: lease)
        try await fixture.session.prune(nowElapsedNS: 0)
        let walPath = fixture.databaseURL.path + "-wal"
        let bytes = (try FileManager.default.attributesOfItem(atPath: walPath)[.size] as? NSNumber)?.int64Value ?? 0
        #expect(bytes == 0)
        #expect(await fixture.session.persistenceQueueSnapshot().acceptsNewReservations)
        try await fixture.session.closeAndDeleteSession()
    }

    @Test func effectiveDatabaseSoftLimitPausesNewReservations() async throws {
        let defaults = try Configuration.bundledDefaults()
        let policy = RetentionPolicy(retention: defaults.retentionSeconds, graceSeconds: defaults.retentionGraceSeconds,
            dbSoftBytes: 1, dbHardBytes: defaults.dbHardBytes,
            walSoftBytes: defaults.walSoftBytes, walHardBytes: defaults.walHardBytes)
        let fixture = try await StorageRegressionFixture.make(retentionPolicy: policy)
        try await fixture.session.prune(nowElapsedNS: 0)
        #expect(!(await fixture.session.persistenceQueueSnapshot().acceptsNewReservations))
        do {
            _ = try await fixture.reserve()
            Issue.record("soft capacity must pause new reservations")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .databaseBackpressure)
            #expect(failure.underlyingCode == "capacity_soft_limit")
        }
        try await fixture.session.closeAndDeleteSession()
    }

    @Test func closeWaitsForAcceptedWriteAndDeletesAllDatabaseFiles() async throws {
        let gate = StorageIOGate()
        let attempts = StorageAttemptLog()
        let fixture = try await StorageRegressionFixture.make { store, batch, sessionID, generation in
            let ordinal = try attempts.record(batch)
            gate.blockFirstOperation()
            if ordinal == 1 {
                throw SQLiteStoreError.execFailed(code: SQLITE_BUSY, message: "busy")
            }
            return try store.commitBatch(batch, sessionID: sessionID, snapshotGeneration: generation)
        }
        let batch = try Fixtures.persistence(id: BatchID(UUID()), value: 70, ms: 100)
        let lease = try await fixture.reserve()
        let write = Task { await storageResult { try await fixture.session.commit(batch, using: lease) } }
        try await storageWaitUntil { gate.isBlocked }
        let close = Task { try await fixture.session.closeAndDeleteSession() }
        try await Task.sleep(nanoseconds: 10_000_000)
        gate.release()
        #expect(await write.value.failure == nil)
        try await close.value
        for suffix in ["", "-wal", "-shm"] {
            #expect(!FileManager.default.fileExists(atPath: fixture.databaseURL.path + suffix))
        }
        try await fixture.session.closeAndDeleteSession()
    }
}

private struct StorageRegressionFixture {
    let session: SessionPersistenceActor
    let databaseURL: URL

    static func make(
        retentionPolicy: RetentionPolicy? = nil,
        operation: @escaping SessionPersistenceActor.BatchCommitOperation = { store, batch, sessionID, generation in
            try store.commitBatch(batch, sessionID: sessionID, snapshotGeneration: generation)
        }
    ) async throws -> StorageRegressionFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StorageRegression-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("session.sqlite")
        let defaults = try Configuration.bundledDefaults()
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(defaults)) as? [String: Any])
        object["database_retry_ms"] = [1, 1, 1, 1, 1]
        let configuration = try JSONDecoder().decode(RuntimeConfiguration.self,
            from: JSONSerialization.data(withJSONObject: object))
        let session = SessionPersistenceActor(databaseURL: url, configuration: configuration, retentionPolicy: retentionPolicy, batchCommitOperation: operation)
        try await session.open(SessionMetadata(sessionID: SessionID(UUID()), startedWallUnixNS: 1,
            model: "Mac16,13", osBuild: "24G419", appVersion: "test"))
        return StorageRegressionFixture(session: session, databaseURL: url)
    }

    func reserve() async throws -> PersistenceLease {
        try await session.reserve(owner: .request(RequestID(UUID())), generation: 1, maxRecords: 512, maxBytes: 1_048_576)
    }
}

private struct StorageResult {
    let receipt: ProcessingReceipt?
    let failure: MonitorFailure?
}

private func storageResult(_ action: () async throws -> ProcessingReceipt) async -> StorageResult {
    do {
        return StorageResult(receipt: try await action(), failure: nil)
    } catch let failure as MonitorFailure {
        return StorageResult(receipt: nil, failure: failure)
    } catch {
        Issue.record("unexpected storage error: \(error)")
        return StorageResult(receipt: nil, failure: nil)
    }
}

private func storageEmptyBatch() -> PersistenceBatch {
    PersistenceBatch(batchID: BatchID(UUID()), sources: [], definitions: [], segments: [],
        raw: [], ema: [], buckets: [], trends: [], gaps: [])
}

private final class StorageAttemptLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedIDs: [BatchID] = []
    private var recordedHashes: [String] = []
    var count: Int { lock.withLock { recordedIDs.count } }
    var batchIDs: [BatchID] { lock.withLock { recordedIDs } }
    var hashes: [String] { lock.withLock { recordedHashes } }
    func record(_ batch: PersistenceBatch) throws -> Int {
        let hash = try BatchCanonicalHash.sha256(for: batch)
        return lock.withLock {
            recordedIDs.append(batch.batchID)
            recordedHashes.append(hash)
            return recordedIDs.count
        }
    }
}

private final class StorageIOGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var operationCount = 0
    private var blocked = false
    private var released = false
    var isBlocked: Bool {
        condition.lock()
        defer { condition.unlock() }
        return blocked
    }
    func blockFirstOperation() {
        condition.lock()
        defer { condition.unlock() }
        operationCount += 1
        guard operationCount == 1 else { return }
        blocked = true
        while !released { condition.wait() }
        blocked = false
    }
    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }
}

private func storageWaitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while !condition() {
        guard ContinuousClock.now < deadline else { throw CocoaError(.fileReadUnknown) }
        try await Task.sleep(nanoseconds: 1_000_000)
    }
}
