import Foundation
import Testing
@testable import SensorRuntime
@testable import TemperatureCore

@Suite(.serialized) struct ProcessingCoordinatorTests {
    @Test func coordinatorAcceptsScheduledReadThroughLeaseAndCommit() async throws {
        let clock = CoordinatorTestClock(now: timestamp(ms: 0))
        let catalog = try makeCatalog(kinds: [.cpuZone])
        let client = MockCoordinatorSensorClient(clock: clock, catalog: catalog)
        let configuration = try Configuration.bundledDefaults()
        let runtime = try makeInMemoryRuntime(clock: clock, configuration: configuration, catalog: catalog)
        let coordinator = ProcessingCoordinator(
            clock: clock,
            client: client,
            reservation: runtime.reservation,
            engine: runtime.engine,
            configuration: configuration
        )

        await coordinator.start(catalog: catalog)
        clock.advance(to: timestamp(ms: 200))
        try await waitUntil { await runtime.commit.acceptCount >= 1 }
        let snapshot = await runtime.engine.snapshot(at: timestamp(ms: 200))
        #expect(snapshot.generation >= 1)
        await coordinator.stop()
    }

    @Test func staleGenerationReadIsDiscardedWithoutAccept() async throws {
        let clock = CoordinatorTestClock(now: timestamp(ms: 0))
        let catalog = try makeCatalog(kinds: [.cpuZone])
        let client = MockCoordinatorSensorClient(
            clock: clock,
            catalog: catalog,
            forcedGeneration: 0
        )
        let configuration = try Configuration.bundledDefaults()
        let runtime = try await makeSessionBackedRuntime(
            clock: clock,
            configuration: configuration,
            catalog: catalog
        )
        let coordinator = ProcessingCoordinator(
            clock: clock,
            client: client,
            reservation: runtime.reservation,
            engine: runtime.engine,
            configuration: configuration
        )

        await coordinator.start(catalog: catalog)
        clock.advance(to: timestamp(ms: 200))
        try await waitUntil { await client.readCount >= 1 }
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(await runtime.commit.acceptCount == 0)
        await coordinator.stop()
    }

    @Test func acceptFailureCancelsLeaseWithoutStateChange() async throws {
        let clock = CoordinatorTestClock(now: timestamp(ms: 0))
        let catalog = try makeCatalog(kinds: [.cpuZone])
        let client = MockCoordinatorSensorClient(clock: clock, catalog: catalog)
        let configuration = try Configuration.bundledDefaults()
        let runtime = try makeInMemoryRuntime(
            clock: clock,
            configuration: configuration,
            catalog: catalog,
            rejectNextAccept: true
        )
        let coordinator = ProcessingCoordinator(
            clock: clock,
            client: client,
            reservation: runtime.reservation,
            engine: runtime.engine,
            configuration: configuration
        )

        await coordinator.start(catalog: catalog)
        clock.advance(to: timestamp(ms: 200))
        try await waitUntil { await client.readCount >= 1 }
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(await runtime.commit.acceptCount == 0)
        let snapshot = await runtime.engine.snapshot(at: timestamp(ms: 200))
        #expect(snapshot.generation == 0)
        await coordinator.stop()
    }
}

private struct CoordinatorRuntime {
    let reservation: PersistenceReservationCapability
    let engine: MonitorEngine
    let commit: CoordinatorCommitSpy
}

private func makeInMemoryRuntime(
    clock: CoordinatorTestClock,
    configuration: RuntimeConfiguration,
    catalog: QualifiedSourceCatalog,
    rejectNextAccept: Bool = false
) throws -> CoordinatorRuntime {
    let commit = CoordinatorCommitSpy(rejectNextAccept: rejectNextAccept)
    let engine = try makeCoordinatorEngine(
        clock: clock,
        commit: commit,
        configuration: configuration,
        catalog: catalog
    )
    return CoordinatorRuntime(
        reservation: NoopReservation(),
        engine: engine,
        commit: commit
    )
}

private func makeSessionBackedRuntime(
    clock: CoordinatorTestClock,
    configuration: RuntimeConfiguration,
    catalog: QualifiedSourceCatalog
) async throws -> CoordinatorRuntime {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ProcessingCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let session = SessionPersistenceActor(
        databaseURL: directory.appendingPathComponent("session.sqlite")
    )
    try await session.open(
        SessionMetadata(
            sessionID: try SessionID(validating: "00000000-0000-4000-8000-000000000702"),
            startedWallUnixNS: 1_700_000_000_000_000_000,
            model: "Mac16,13",
            osBuild: "24G419",
            appVersion: "0.1.0-test"
        )
    )
    let commit = CoordinatorCommitSpy()
    let engine = try makeCoordinatorEngine(
        clock: clock,
        commit: commit,
        configuration: configuration,
        catalog: catalog
    )
    return CoordinatorRuntime(
        reservation: await session.reservationCapability(),
        engine: engine,
        commit: commit
    )
}

private func makeCoordinatorEngine(
    clock: CoordinatorTestClock,
    commit: CoordinatorCommitSpy,
    configuration: RuntimeConfiguration,
    catalog: QualifiedSourceCatalog
) throws -> MonitorEngine {
    let sourceID = try #require(catalog.available.first?.sourceID)
    return MonitorEngine(
        clock: clock,
        commit: commit,
        session: SessionMetadata(
            sessionID: try SessionID(validating: "00000000-0000-4000-8000-000000000701"),
            startedWallUnixNS: 1_700_000_000_000_000_000,
            model: "Mac16,13",
            osBuild: "24G419",
            appVersion: "0.1.0-test"
        ),
        configuration: configuration,
        definitions: [
            SeriesDefinition(
                seriesID: SeriesID(CoordinatorFixtures.uuid(101)),
                metricID: try MetricID(validating: "fixture.cpu"),
                definitionVersion: 1,
                kind: .cpuZone,
                displayName: "测试来源",
                memberSourceIDs: [sourceID],
                formula: .identity
            )
        ],
        cpuPeriodMS: configuration.cpuDefaultMS
    )
}

private func makeCatalog(kinds: [SensorKind]) throws -> QualifiedSourceCatalog {
    var available: [QualifiedSource] = []
    for (index, kind) in kinds.enumerated() {
        available.append(
            QualifiedSource(
                sourceID: SourceID(CoordinatorFixtures.uuid(10 + index)),
                transportHandle: "mock:\(kind.rawValue)-\(index)",
                provider: .smc,
                rawKey: "Tp0\(index)",
                registryID: nil,
                connectionGeneration: 1,
                kind: kind,
                encoding: "flt ",
                unitEvidence: "test",
                evidence: .targetQualified,
                mappingVersion: "test-v1"
            )
        )
    }
    return QualifiedSourceCatalog(generation: 1, available: available, unavailable: [])
}

private func timestamp(ms: Int64) -> Timestamp {
    Timestamp(elapsedNS: ms * 1_000_000, wallUnixNS: ms * 1_000_000)
}

private func waitUntil(
    timeoutMS: Int64 = 500,
    _ predicate: @escaping () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(Double(timeoutMS) / 1000)
    while Date() < deadline {
        if await predicate() {
            return
        }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
    Issue.record("condition not met before timeout")
}

private enum CoordinatorFixtures {
    static func uuid(_ ordinal: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", ordinal))!
    }
}

private actor NoopReservation: PersistenceReservationCapability {
    func reserve(
        owner: PersistenceOwner,
        generation: UInt64,
        maxRecords: Int,
        maxBytes: Int
    ) async throws -> PersistenceLease {
        PersistenceLease(
            reservationID: UUID(),
            owner: owner,
            generation: generation,
            maxRecords: maxRecords,
            maxBytes: maxBytes
        )
    }

    func cancel(_ lease: PersistenceLease) async {
        _ = lease
    }
}

private actor CoordinatorCommitSpy: PersistenceCommitCapability {
    private(set) var acceptCount = 0
    private var rejectNextAccept: Bool
    private var snapshotGeneration: UInt64 = 0

    init(rejectNextAccept: Bool = false) {
        self.rejectNextAccept = rejectNextAccept
    }

    func commit(_ batch: PersistenceBatch, using lease: PersistenceLease) async throws -> ProcessingReceipt {
        _ = lease
        if !batch.raw.isEmpty, rejectNextAccept {
            rejectNextAccept = false
            throw MonitorFailure(
                code: .databaseIntegrity,
                severity: .fatal,
                component: "CoordinatorCommitSpy",
                operation: "commit",
                retryCount: 0,
                sourceID: nil,
                underlyingCode: "forced_reject"
            )
        }
        if !batch.raw.isEmpty {
            acceptCount += 1
        }
        snapshotGeneration += 1
        let recordCount = batch.raw.count + batch.ema.count + batch.buckets.count + batch.trends.count + batch.gaps.count
        return ProcessingReceipt(
            batchID: batch.batchID,
            acceptedRecords: recordCount,
            snapshotGeneration: snapshotGeneration
        )
    }
}

final class CoordinatorTestClock: MonitorClock, @unchecked Sendable {
    private struct Waiter {
        let deadline: Int64
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var current: Timestamp
    private var waiters: [UUID: Waiter] = [:]

    init(now: Timestamp) {
        current = now
    }

    func now() -> Timestamp {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func sleep(untilElapsedNS: Int64) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if untilElapsedNS <= current.elapsedNS {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                waiters[id] = Waiter(deadline: untilElapsedNS, continuation: continuation)
                lock.unlock()
            }
        } onCancel: {
            lock.lock()
            if let waiter = waiters.removeValue(forKey: id) {
                lock.unlock()
                waiter.continuation.resume(throwing: CancellationError())
            } else {
                lock.unlock()
            }
        }
    }

    func advance(to timestamp: Timestamp) {
        lock.lock()
        if timestamp.elapsedNS < current.elapsedNS {
            lock.unlock()
            return
        }
        current = timestamp
        let due = waiters.filter { $0.value.deadline <= current.elapsedNS }
        for key in due.keys {
            waiters.removeValue(forKey: key)
        }
        lock.unlock()
        for waiter in due.values {
            waiter.continuation.resume()
        }
    }
}

actor MockCoordinatorSensorClient: SensorClient {
    let clock: CoordinatorTestClock
    let catalog: QualifiedSourceCatalog
    let readDurationMS: Int64
    let forcedGeneration: UInt64?
    private(set) var readCount = 0
    private(set) var lastReadKind: SamplingScheduleKind?

    init(
        clock: CoordinatorTestClock,
        catalog: QualifiedSourceCatalog,
        readDurationMS: Int64 = 0,
        forcedGeneration: UInt64? = nil
    ) {
        self.clock = clock
        self.catalog = catalog
        self.readDurationMS = readDurationMS
        self.forcedGeneration = forcedGeneration
    }

    func discover() async throws -> QualifiedSourceCatalog {
        catalog
    }

    func read(_ request: ReadRequest) async throws -> ReadBatch {
        readCount += 1
        let started = clock.now()
        if readDurationMS > 0 {
            let target = started.elapsedNS + readDurationMS * 1_000_000
            try await clock.sleep(untilElapsedNS: target)
        }
        let finished = clock.now()
        let readings = request.sourceIDs.map { sourceID in
            Reading(
                sourceID: sourceID,
                started: started,
                finished: finished,
                outcome: .success(valueC: 80, sourceWallUnixNS: nil, freshness: .unknown)
            )
        }
        return ReadBatch(
            requestID: request.requestID,
            generation: forcedGeneration ?? catalog.generation,
            readings: readings
        )
    }

    func close() async {}
}
