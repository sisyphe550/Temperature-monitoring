import Foundation
import Testing
@testable import SensorRuntime
@testable import TemperatureCore

@Suite(.serialized) struct OptionalAvailabilityIntegrationTests {
    @Test(arguments: [false, true])
    func optionalRecoveryRequiresThreeCommittedReadsAndKeepsCPUAlive(rejectThirdReceipt: Bool) async throws {
        let clock = QuarantineClock(now: Fixtures.timestamp(ms: 0))
        let ssdID = SourceID(Fixtures.uuid(2))
        let ssdSeriesID = SeriesID(Fixtures.uuid(2))
        let catalog = QualifiedSourceCatalog(generation: 1, available: [Fixtures.source(),
            QualifiedSource(sourceID: ssdID, transportHandle: "fixture:ssd", provider: .nvme, rawKey: "CompositeTemperature",
                registryID: "fixture-nvme", connectionGeneration: 1, kind: .ssd, encoding: "nvmeKelvin",
                unitEvidence: "fixture-celsius", evidence: .targetQualified, mappingVersion: "fixture-v1")], unavailable: [])
        let client = QuarantineSensorClient(clock: clock, catalog: catalog)
        let gate = OptionalReceiptGate(seriesID: ssdSeriesID, reject: rejectThirdReceipt)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OptionalController-\(UUID())")
        let session = SessionPersistenceActor(databaseURL: root.appendingPathComponent("session.sqlite"),
            configuration: try Configuration.bundledDefaults(), batchCommitOperation: { store, batch, sessionID, generation in
                try gate.beforeCommit(batch)
                let result = try store.commitBatch(batch, sessionID: sessionID, snapshotGeneration: generation)
                gate.afterCommit(batch)
                return result
            })
        let controller = SessionMonitorController(clock: clock, client: client, session: session,
            sessionMetadata: SessionMetadata(sessionID: SessionID(UUID()), startedWallUnixNS: 1,
                model: "Mac16,13", osBuild: "24G419", appVersion: "regression"), configuration: try Configuration.bundledDefaults())
        let snapshots = QuarantineSnapshotLog()
        let stream = await controller.snapshots()
        let observer = Task { for await snapshot in stream { await snapshots.append(snapshot) } }
        do {
            try await controller.start()
            defer { gate.release() }
            clock.advance(to: Fixtures.timestamp(ms: 500))
            for retryMS in [Int64(550), 650, 850] {
                // A read count does not mean its failed Receipt has returned.
                // Wait until Sampling has actually requested the retry sleep.
                try await quarantineWaitUntil {
                    retryMS == 550 ? clock.identifySamplingTask(waitingUntilMS: retryMS) : clock.hasSamplingSleep(untilMS: retryMS)
                }
                clock.advance(to: Fixtures.timestamp(ms: retryMS))
            }
            // Sampling sleeps again only after the fourth failure Receipt,
            // quarantine transition and the following CPU read are complete.
            try await quarantineWaitUntil { clock.hasSamplingSleep(untilMS: 1000) }
            clock.advance(to: Fixtures.timestamp(ms: 1000))
            try await quarantineWaitUntil { clock.hasSamplingSleep(untilMS: 1200) }
            #expect(await client.optionalReads == 4)
            try await quarantineWaitUntil { await snapshots.hasUnavailableSSD }
            #expect(try await session.rows(in: "raw_samples") > 0)
            let cpuReadsBeforeQuarantine = await client.cpuReads
            for ms in [Int64(2000), 4000, 10_000] {
                let previousCount = await client.cpuReads
                clock.advance(to: Fixtures.timestamp(ms: ms))
                try await quarantineWaitUntil { await client.cpuReads > previousCount }
                try await quarantineWaitUntil { clock.hasSamplingSleep(untilMS: ms + 200) }
            }
            #expect(await client.optionalReads == 4)
            let cpuAfterQuarantine = await client.cpuReads
            let runtimeFailure = await controller.lastAcceptFailure()
            #expect(cpuAfterQuarantine > cpuReadsBeforeQuarantine, "CPU before=\(cpuReadsBeforeQuarantine) after=\(cpuAfterQuarantine), failure=\(String(describing: runtimeFailure))")
            // First valid probe happens at exhausted time + 60s; the following
            // two reads use the normal 500ms interval with the same source.
            for (readMS, publishMS, schedulerMS, expectedReads) in [
                (Int64(61_000), Int64(61_200), Int64(61_200), 5),
                (61_500, 61_700, 61_600, 6)
            ] {
                clock.advance(to: Fixtures.timestamp(ms: readMS))
                try await quarantineWaitUntil { await client.optionalReads >= expectedReads && gate.completedSSDCalls >= expectedReads - 4 }
                // A new scheduler sleep proves the entire read callback and
                // probe transition completed, including the next SSD deadline.
                try await quarantineWaitUntil {
                    clock.hasSamplingSleep(untilMS: schedulerMS)
                }
                clock.advance(to: Fixtures.timestamp(ms: publishMS))
                try await quarantineWaitUntil { await snapshots.latestElapsedNS >= publishMS * 1_000_000 }
                #expect(await snapshots.hasUnavailableSSD)
                try await quarantineWaitUntil { clock.hasSamplingSleep(untilMS: (publishMS / 200 + 1) * 200) }
            }
            #expect(gate.completedSSDCalls == 2)
            clock.advance(to: Fixtures.timestamp(ms: 62_000))
            try await quarantineWaitUntil { gate.isBlocked }
            #expect(await client.optionalReads == 7)
            #expect(await snapshots.hasUnavailableSSD)
            #expect(gate.completedSSDCalls == 2)
            gate.release()
            if rejectThirdReceipt {
                try await quarantineWaitUntil { await controller.lastAcceptFailure()?.severity == .fatal }
                clock.advance(to: Fixtures.timestamp(ms: 62_200))
                try await quarantineWaitUntil { await snapshots.latestElapsedNS >= 62_200_000_000 }
                #expect(await snapshots.hasUnavailableSSD, "A rejected third Receipt must keep the optional source unavailable")
                #expect(gate.completedSSDCalls == 2)
            } else {
                try await quarantineWaitUntil { gate.completedSSDCalls == 3 }
                try await quarantineWaitUntil { clock.hasSamplingSleep(untilMS: 62_200) }
                clock.advance(to: Fixtures.timestamp(ms: 62_200))
                try await quarantineWaitUntil { await snapshots.hasAvailableSnapshot(atLeastNS: 62_200_000_000) }
                #expect(await controller.lastAcceptFailure() == nil)
                #expect(await snapshots.hasAvailableSSD)
            }
            await controller.stop()
            await observer.value
            #expect(await session.persistenceQueueSnapshot().totalRecords == 0)
        } catch {
            gate.release()
            await controller.stop()
            observer.cancel()
            await observer.value
            throw error
        }
    }
}

private actor QuarantineSensorClient: SensorClient {
    let clock: QuarantineClock
    let catalog: QualifiedSourceCatalog
    private(set) var optionalReads = 0
    private(set) var cpuReads = 0
    init(clock: QuarantineClock, catalog: QualifiedSourceCatalog) { self.clock = clock; self.catalog = catalog }
    func discover() async throws -> QualifiedSourceCatalog { catalog }
    func read(_ request: ReadRequest) async throws -> ReadBatch {
        let isCPU = request.sourceIDs.contains(SourceID(Fixtures.uuid(1)))
        if isCPU { cpuReads += 1 }
        else {
            optionalReads += 1
            if optionalReads <= 4 {
                throw MonitorFailure(code: .sensorRead, severity: .degraded, component: "fixture", operation: "read",
                    retryCount: 0, sourceID: request.sourceIDs.first, underlyingCode: "optional_io_failure")
            }
        }
        let timestamp = clock.now()
        return ReadBatch(requestID: request.requestID, generation: catalog.generation, requestedPeriodMS: request.requestedPeriodMS,
            readings: request.sourceIDs.map { Reading(sourceID: $0, started: timestamp, finished: timestamp,
                outcome: .success(valueC: 60, sourceWallUnixNS: nil, freshness: .unknown)) })
    }
    func close() async {}
}

private actor QuarantineSnapshotLog {
    private var latest: Snapshot?
    func append(_ snapshot: Snapshot) { latest = snapshot }
    var latestElapsedNS: Int64 { latest?.asOf.elapsedNS ?? -1 }
    var hasUnavailableSSD: Bool {
        guard let state = latest?.values.first(where: { $0.definition.kind == .ssd })?.state else { return false }
        if case .unavailable(capability: .failed, reason: _) = state { return true }
        return false
    }
    func hasAvailableSnapshot(atLeastNS: Int64) -> Bool {
        latestElapsedNS >= atLeastNS && hasAvailableSSD
    }
    var hasAvailableSSD: Bool {
        guard let state = latest?.values.first(where: { $0.definition.kind == .ssd })?.state else { return false }
        if case .available = state { return true }
        return false
    }
}

private final class OptionalReceiptGate: @unchecked Sendable {
    private let condition = NSCondition()
    private let seriesID: SeriesID
    private let reject: Bool
    private var calls = 0
    private var completed = 0
    private var blocked = false
    private var released = false
    init(seriesID: SeriesID, reject: Bool) { self.seriesID = seriesID; self.reject = reject }
    var isBlocked: Bool { condition.withLock { blocked } }
    var completedSSDCalls: Int { condition.withLock { completed } }
    func beforeCommit(_ batch: PersistenceBatch) throws {
        guard batch.raw.contains(where: { $0.seriesID == seriesID }) else { return }
        condition.lock()
        defer { condition.unlock() }
        calls += 1
        if calls == 3 {
            blocked = true
            while !released { condition.wait() }
            blocked = false
            if reject { throw SQLiteStoreError.integrityConflict(detail: "third optional receipt rejected") }
        }
    }
    func afterCommit(_ batch: PersistenceBatch) {
        guard batch.raw.contains(where: { $0.seriesID == seriesID }) else { return }
        condition.withLock { completed += 1 }
    }
    func release() { condition.withLock { released = true; condition.broadcast() } }
}

private func quarantineWaitUntil(line: Int = #line, _ predicate: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while !(await predicate()) {
        guard ContinuousClock.now < deadline else {
            Issue.record("optional controller condition timed out from line \(line)")
            throw CocoaError(.fileReadUnknown)
        }
        try await Task.sleep(for: .milliseconds(2))
    }
}

// Track sleep registration without changing production clocks or the shared
// TestClock. Advancing only after registration makes async IO completion explicit.
private final class QuarantineClock: MonitorClock, @unchecked Sendable {
    private struct Sleep {
        let deadline: Int64
        let taskHash: Int?
    }
    private let base: TestClock
    private let lock = NSLock()
    private var sleepers: [UUID: Sleep] = [:]
    private var samplingTaskHash: Int?
    init(now: Timestamp) { base = TestClock(now: now) }
    func now() -> Timestamp { base.now() }
    func advance(to timestamp: Timestamp) { base.advance(to: timestamp) }
    func sleep(untilElapsedNS: Int64) async throws {
        let id = UUID()
        let taskHash = withUnsafeCurrentTask { $0?.hashValue }
        lock.withLock { sleepers[id] = Sleep(deadline: untilElapsedNS, taskHash: taskHash) }
        defer { lock.withLock { _ = sleepers.removeValue(forKey: id) } }
        try await base.sleep(untilElapsedNS: untilElapsedNS)
    }
    func identifySamplingTask(waitingUntilMS: Int64) -> Bool {
        lock.withLock {
            // The 50ms retry deadline uniquely identifies the sampling task;
            // snapshot and watermark loops have separate task identities.
            guard let sleep = sleepers.values.first(where: { $0.deadline == waitingUntilMS * 1_000_000 }),
                  let taskHash = sleep.taskHash else { return false }
            samplingTaskHash = taskHash
            return true
        }
    }
    func hasSamplingSleep(untilMS: Int64) -> Bool {
        lock.withLock {
            guard let taskHash = samplingTaskHash else { return false }
            return sleepers.values.contains { $0.deadline == untilMS * 1_000_000 && $0.taskHash == taskHash }
        }
    }
}
