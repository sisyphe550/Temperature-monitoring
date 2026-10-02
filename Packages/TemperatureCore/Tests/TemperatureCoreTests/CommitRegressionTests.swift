import Foundation
import Testing
@testable import TemperatureCore

@Suite struct CommitRegressionTests {
    @Test func failedReadCommitCanRetryWithoutAdvancingSamplesOrSequence() async throws {
        let (engine, commit) = try makeEngine()
        let id = RequestID(UUID())
        let batch = Fixtures.read(id: id, ms: 200, values: [70])
        await commit.failNext()
        await #expect(throws: CommitProbe.Failure.self) { try await engine.accept(batch, lease: lease(.request(id))) }
        #expect(await engine.rawSamples(for: SeriesID(Fixtures.uuid(101)), nowElapsedNS: 200_000_000).isEmpty)
        let receipt = try await engine.accept(batch, lease: lease(.request(id)))
        let written = try #require(await commit.batch(receipt.batchID))
        #expect(written.raw.count == 1)
        #expect(written.raw[0].sampleID.hasSuffix(":1"))
        #expect(written.ema[0].valueC == 70)
        #expect(await engine.snapshot(at: Fixtures.timestamp(ms: 200)).generation == 1)
    }

    @Test func failedAggregationCommitRetainsWindowForRetry() async throws {
        let (engine, commit) = try makeEngine()
        let id = RequestID(UUID())
        _ = try await engine.accept(Fixtures.read(id: id, ms: 200, values: [70]), lease: lease(.request(id)))
        await commit.failNext()
        let watermark = WatermarkEventID(UUID())
        await #expect(throws: CommitProbe.Failure.self) {
            try await engine.advance(to: Fixtures.timestamp(ms: 1000), lease: lease(.watermark(watermark)))
        }
        let receipt = try await engine.advance(to: Fixtures.timestamp(ms: 1000), lease: lease(.watermark(watermark)))
        let written = try #require(await commit.batch(receipt.batchID))
        try #require(written.buckets.count == 1)
        #expect(written.buckets[0].count == 1)
        #expect(written.buckets[0].latestC == 70)
    }

    @Test func preparingOrFailingWakeDoesNotAdvanceSegment() async throws {
        let (engine, commit) = try makeEngine()
        let id = RequestID(UUID())
        _ = try await engine.accept(Fixtures.read(id: id, ms: 200, values: [70]), lease: lease(.request(id)))
        let gaps = try await engine.openSleepGaps(at: Fixtures.timestamp(ms: 400))
        _ = try await engine.commitLifecycleTransition(gaps: gaps, segments: [], lease: lease(.gap(GapID(UUID()))))
        let transition = try await engine.closeOpenGapsForWake(at: Fixtures.timestamp(ms: 5000))
        await commit.failNext()
        await #expect(throws: CommitProbe.Failure.self) {
            try await engine.commitLifecycleTransition(gaps: transition.gaps, segments: transition.segments, lease: lease(.gap(GapID(UUID()))))
        }
        let retry = try await engine.closeOpenGapsForWake(at: Fixtures.timestamp(ms: 5000))
        #expect(retry.segments.map(\.number) == [2])
        _ = try await engine.commitLifecycleTransition(gaps: retry.gaps, segments: retry.segments, lease: lease(.gap(GapID(UUID()))))
        let next = RequestID(UUID())
        let receipt = try await engine.accept(Fixtures.read(id: next, ms: 5200, values: [80]), lease: lease(.request(next)))
        let written = try #require(await commit.batch(receipt.batchID))
        #expect(written.raw[0].segment == 2)
        #expect(written.ema[0].valueC == 80)
    }

    @Test func inFlightRegistrationSurvivesAggregationCommit() async throws {
        let (engine, commit) = try makeEngine()
        await commit.holdNext()
        let advance = Task { try await engine.advance(to: Fixtures.timestamp(ms: 1000), lease: lease(.watermark(WatermarkEventID(UUID())))) }
        await commit.waitUntilHeld()
        await engine.registerInFlightReading(startElapsedNS: 1_200_000_000)
        await commit.release()
        _ = try await advance.value
        #expect(await engine.safeWatermarkElapsedNS(at: Fixtures.timestamp(ms: 3000)) == 1_999_999_999)
        await engine.unregisterInFlightReading(startElapsedNS: 1_200_000_000)
        #expect(await engine.safeWatermarkElapsedNS(at: Fixtures.timestamp(ms: 3000)) == 3_000_000_000)
    }

    @Test func concurrentAcceptsCommitDistinctSampleIDsAndOrderedEMA() async throws {
        let (engine, commit) = try makeEngine()
        await commit.holdNext()
        let firstID = RequestID(UUID())
        let first = Task { try await engine.accept(Fixtures.read(id: firstID, ms: 200, values: [70]), lease: lease(.request(firstID))) }
        await commit.waitUntilHeld()
        let secondID = RequestID(UUID())
        let second = Task { try await engine.accept(Fixtures.read(id: secondID, ms: 400, values: [80]), lease: lease(.request(secondID))) }
        await Task.yield()
        await commit.release()
        _ = try await first.value
        _ = try await second.value
        let values = await engine.rawSamples(for: SeriesID(Fixtures.uuid(101)), nowElapsedNS: 400_000_000)
        #expect(values.map(\.valueC) == [70, 80])
        #expect(Set(values.map(\.sampleID)).count == 2)
        let ema = await engine.emaSamples(for: SeriesID(Fixtures.uuid(101)), nowElapsedNS: 400_000_000)
        try #require(ema.count == 2)
        #expect(ema[1].valueC > 70 && ema[1].valueC < 80)
    }

    @Test func pendingCPUReadUsesItsRequestedPeriodAfterPickerChanges() async throws {
        let fixture = try await ProcessorFixture.make(cpuMembers: 12)
        await fixture.engine.setCPUPeriod(milliseconds: 1000)
        let id = RequestID(UUID())
        let receipt = try await fixture.accept(Fixtures.read(id: id, ms: 200, values: Array(repeating: 70, count: 12)), lease: fixture.lease(owner: .request(id), generation: 1))
        let batch = try #require(await fixture.committedBatch(for: receipt))
        #expect(batch.raw.count == 13)
        #expect(batch.raw.allSatisfy { $0.periodMS == 200 })
    }

    private func makeEngine() throws -> (MonitorEngine, CommitProbe) {
        let commit = CommitProbe()
        let engine = MonitorEngine(clock: TestClock(now: Fixtures.timestamp(ms: 0)), commit: commit,
            session: SessionMetadata(sessionID: SessionID(UUID()), startedWallUnixNS: 1, model: "Mac16,13", osBuild: "24G419", appVersion: "regression"),
            configuration: try Configuration.bundledDefaults(), definitions: [try Fixtures.definition()], cpuPeriodMS: 200)
        return (engine, commit)
    }

    private func lease(_ owner: PersistenceOwner) -> PersistenceLease {
        PersistenceLease(reservationID: UUID(), owner: owner, generation: 1, maxRecords: 512, maxBytes: 33_554_432)
    }
}

private actor CommitProbe: PersistenceCommitCapability {
    enum Failure: Error { case temporaryWrite }
    private var shouldFail = false
    private var shouldHold = false
    private var held: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []
    private var committed: [PersistenceBatch] = []
    func failNext() { shouldFail = true }
    func holdNext() { shouldHold = true }
    func waitUntilHeld() async {
        if held != nil { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func release() { held?.resume(); held = nil }
    func batch(_ id: BatchID) -> PersistenceBatch? { committed.first { $0.batchID == id } }
    func commit(_ batch: PersistenceBatch, using lease: PersistenceLease) async throws -> ProcessingReceipt {
        if shouldFail { shouldFail = false; throw Failure.temporaryWrite }
        if shouldHold {
            shouldHold = false
            await withCheckedContinuation { held = $0; observers.forEach { $0.resume() }; observers.removeAll() }
        }
        committed.append(batch)
        return ProcessingReceipt(batchID: batch.batchID, acceptedRecords: PersistenceBatchMetrics.logicalRecordCount(batch), snapshotGeneration: UInt64(committed.count))
    }
}
