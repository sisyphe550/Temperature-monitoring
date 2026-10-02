import Foundation
import Testing
@testable import TemperatureCore

@Suite struct EngineGapRegressionTests {
    @Test func explicitReadFailureOpensOneGapAndRecoveryResetsEMA() async throws {
        let f = try GapEngineFixture.make()
        _ = try await f.accept(ms: 200, values: [50])
        let failed = try await f.accept(ms: 400, values: [nil])
        let failureBatch = try #require(await f.commit.batch(failed.batchID))
        #expect(failureBatch.raw.isEmpty && failureBatch.ema.isEmpty)
        let opened = try #require(failureBatch.gaps.first)
        #expect(opened.endedElapsedNS == nil)
        _ = try await f.accept(ms: 600, values: [nil])
        #expect(await f.engine.snapshot(at: Fixtures.timestamp(ms: 600)).gapIDs == [opened.gapID])
        let receipt = try await f.accept(ms: 800, values: [80])
        let recovered = try #require(await f.commit.batch(receipt.batchID))
        #expect(recovered.gaps.map(\.gapID) == [opened.gapID])
        #expect(recovered.gaps.first?.endedElapsedNS == 800_000_000)
        #expect(recovered.segments.contains { $0.seriesID == f.seriesID && $0.number == 2 })
        #expect(recovered.raw.first?.segment == 2)
        #expect(recovered.ema.first?.valueC == 80)
        #expect(await f.engine.snapshot(at: Fixtures.timestamp(ms: 800)).gapIDs.isEmpty)
        let history = await f.engine.historyGapsFor(request: f.history(atMS: 800))
        #expect(history.map(\.gapID) == [opened.gapID])
        #expect(history.first?.endedElapsedNS == 800_000_000)
    }

    @Test func elapsedTimeoutPersistsClosedGapAndNewSegmentWithSamples() async throws {
        let f = try GapEngineFixture.make()
        _ = try await f.accept(ms: 200, values: [50])
        let receipt = try await f.accept(ms: 1400, values: [90])
        let batch = try #require(await f.commit.batch(receipt.batchID))
        #expect(batch.gaps.count == 1)
        #expect(batch.gaps.first?.reason == .timeout)
        #expect(batch.gaps.first?.endedElapsedNS == 1_400_000_000)
        #expect(batch.segments.first?.number == 2)
        #expect(batch.raw.first?.segment == 2)
        #expect(batch.ema.first?.valueC == 90)
    }

    @Test func normalLongerPeriodDoesNotCreateFalseGap() async throws {
        let f = try GapEngineFixture.make()
        _ = try await f.accept(ms: 200, values: [50], periodMS: 200)
        let receipt = try await f.accept(ms: 3000, values: [90], periodMS: 1000)
        let batch = try #require(await f.commit.batch(receipt.batchID))
        #expect(batch.gaps.isEmpty)
        #expect(batch.raw.first?.segment == 1)
        #expect((batch.ema.first?.valueC ?? 0) < 90)
    }

    @Test func failedCPU12MemberAlsoGapsMaximumAndRecoveryUsesRawMaximum() async throws {
        let f = try GapEngineFixture.make(cpuMembers: 12)
        _ = try await f.accept(ms: 200, values: Array(repeating: 50, count: 12))
        var values: [Double?] = Array(repeating: 60, count: 12)
        values[2] = nil
        let failed = try await f.accept(ms: 400, values: values)
        let batch = try #require(await f.commit.batch(failed.batchID))
        #expect(batch.gaps.count == 2)
        #expect(batch.gaps.contains { $0.seriesID == f.maximumID })
        #expect(!batch.raw.contains { $0.seriesID == f.maximumID })
        let recovered = try await f.accept(ms: 600, values: Array(repeating: 80, count: 12))
        let recovery = try #require(await f.commit.batch(recovered.batchID))
        #expect(recovery.raw.first { $0.seriesID == f.maximumID }?.segment == 2)
        #expect(recovery.ema.first { $0.seriesID == f.maximumID }?.valueC == 80)
        #expect(recovery.gaps.count == 2)
        #expect(recovery.segments.count == 2)
    }

    @Test func rejectedRecoveryReceiptDoesNotLeakSegmentOrCloseGap() async throws {
        let f = try GapEngineFixture.make()
        _ = try await f.accept(ms: 200, values: [50])
        let failed = try await f.accept(ms: 400, values: [nil])
        let opened = try #require(await f.commit.batch(failed.batchID)?.gaps.first)
        await f.commit.rejectNext()
        await #expect(throws: MonitorFailure.self) { try await f.accept(ms: 600, values: [90]) }
        let snapshot = await f.engine.snapshot(at: Fixtures.timestamp(ms: 600))
        #expect(snapshot.gapIDs == [opened.gapID])
        #expect(await f.engine.rawSamples(for: f.seriesID, nowElapsedNS: 600_000_000).count == 1)
        #expect(await f.engine.historyGapsFor(request: f.history(atMS: 600)).first?.endedElapsedNS == nil)
        let retried = try await f.accept(ms: 600, values: [90])
        let recovery = try #require(await f.commit.batch(retried.batchID))
        #expect(recovery.raw.first?.segment == 2)
        #expect(recovery.raw.first?.sampleID.hasSuffix(":2") == true)
        #expect(recovery.ema.first?.valueC == 90)
    }

    @Test func failedGapReceiptDoesNotPublishGapAndRetryOnlyOpensOne() async throws {
        let f = try GapEngineFixture.make()
        _ = try await f.accept(ms: 200, values: [50])
        await f.commit.failNext()
        await #expect(throws: GapCommitProbe.Failure.self) { try await f.accept(ms: 400, values: [nil]) }
        #expect(await f.engine.snapshot(at: Fixtures.timestamp(ms: 400)).gapIDs.isEmpty)
        #expect(await f.engine.historyGapsFor(request: f.history(atMS: 400)).isEmpty)
        _ = try await f.accept(ms: 400, values: [nil])
        _ = try await f.accept(ms: 600, values: [nil])
        #expect(await f.engine.snapshot(at: Fixtures.timestamp(ms: 600)).gapIDs.count == 1)
        #expect(await f.engine.historyGapsFor(request: f.history(atMS: 600)).count == 1)
    }

    @Test func manualGapClosurePersistsSegmentAndStartsAtInclusiveEnd() async throws {
        let f = try GapEngineFixture.make()
        _ = try await f.accept(ms: 200, values: [50])
        let gapID = GapID(UUID())
        let open = Gap(gapID: gapID, seriesID: f.seriesID, startedElapsedNS: 400_000_000, endedElapsedNS: nil, reason: .overload)
        _ = try await f.engine.markGap(open, lease: f.lease(.gap(gapID)))
        let closed = Gap(gapID: gapID, seriesID: f.seriesID, startedElapsedNS: 400_000_000, endedElapsedNS: 600_000_000, reason: .overload)
        let receipt = try await f.engine.markGap(closed, lease: f.lease(.gap(gapID)))
        #expect(await f.commit.batch(receipt.batchID)?.segments.first?.number == 2)
        #expect(await f.engine.snapshot(at: Fixtures.timestamp(ms: 600)).gapIDs.isEmpty)
        let recovered = try await f.accept(ms: 600, values: [90])
        #expect(await f.commit.batch(recovered.batchID)?.ema.first?.valueC == 90)
    }

    @Test func lifecycleGapHistoryRetainsReasonAndExpiresClosedGaps() async throws {
        let f = try GapEngineFixture.make()
        _ = try await f.accept(ms: 200, values: [nil])
        let open = try #require(await f.engine.historyGapsFor(request: f.history(atMS: 200)).first)
        let transition = try await f.engine.closeOpenGapsForWake(at: Fixtures.timestamp(ms: 5000))
        #expect(transition.gaps.first?.reason == .readFailure)
        _ = try await f.engine.commitLifecycleTransition(gaps: transition.gaps, segments: transition.segments,
            lease: f.lease(.gap(GapID(UUID()))))
        #expect(await f.engine.historyGapsFor(request: f.history(atMS: 5000)).map(\.gapID) == [open.gapID])
        #expect(await f.engine.historyGapsFor(request: f.history(atMS: 305000)).isEmpty)
        let sleep = try await f.engine.openSleepGaps(at: Fixtures.timestamp(ms: 305000))
        _ = try await f.engine.commitLifecycleTransition(gaps: sleep, segments: [], lease: f.lease(.gap(GapID(UUID()))))
        #expect(await f.engine.historyGapsFor(request: f.history(atMS: 700000)).count == 1)
        let other = HistoryRequest(seriesIDs: [SeriesID(UUID())], range: .fiveMinutes, asOfElapsedNS: 700_000_000_000, pointLimit: 100)
        #expect(await f.engine.historyGapsFor(request: other).isEmpty)
    }

    @Test func actualSQLiteStoresFailureAndRecoveryGapWithItsSegment() async throws {
        let store = try await TemporaryStoreFixture.make()
        let clock = TestClock(now: Fixtures.timestamp(ms: 0))
        let metadata = try #require(await store.session.openedSessionMetadata)
        let engine = MonitorEngine(clock: clock, commit: await store.session.commitCapability(), session: metadata,
            configuration: try Configuration.bundledDefaults(), definitions: [try Fixtures.definition()], cpuPeriodMS: 200,
            qualifiedSources: [Fixtures.source()])
        for (ms, value) in [(Int64(200), Optional(50.0)), (400, nil), (800, 90.0)] {
            let id = RequestID(UUID())
            let reading = Reading(sourceID: SourceID(Fixtures.uuid(1)), started: Fixtures.timestamp(ms: ms), finished: Fixtures.timestamp(ms: ms),
                outcome: value.map { .success(valueC: $0, sourceWallUnixNS: nil, freshness: .unknown) } ?? .failure(GapEngineFixture.readFailure()))
            let lease = try await store.session.reserve(owner: .request(id), generation: 1, maxRecords: 512, maxBytes: 1_048_576)
            _ = try await engine.accept(ReadBatch(requestID: id, generation: 1, requestedPeriodMS: 200, readings: [reading]), lease: lease)
            clock.advance(to: Fixtures.timestamp(ms: ms))
        }
        let lease = try await store.session.reserve(owner: .watermark(WatermarkEventID(UUID())), generation: 1, maxRecords: 512, maxBytes: 1_048_576)
        _ = try await engine.advance(to: Fixtures.timestamp(ms: 1000), lease: lease)
        #expect(try await store.rows(in: "raw_samples") == 2)
        #expect(try await store.rows(in: "ema_samples") == 2)
        #expect(try await store.rows(in: "gaps") == 1)
        #expect(try await store.rows(in: "segments") == 2)
        let history = try await store.session.query(HistoryRequest(seriesIDs: [SeriesID(Fixtures.uuid(101))], range: .oneHour,
            asOfElapsedNS: 1_000_000_000, pointLimit: 100))
        #expect(history.gaps.first?.endedElapsedNS == 800_000_000)
        #expect(Set(history.points.map(\.segment)) == [1, 2])
        #expect(history.points.first { $0.segment == 2 }?.valueC == 90)
        try await store.closeAndDeleteSession()
    }

    @Test func optionalAvailabilityRequiresExplicitRecoveryEvenAfterValidReads() async throws {
        let f = try GapEngineFixture.make(kind: .ssd)
        _ = try await f.accept(ms: 200, values: [50])
        let failure = GapEngineFixture.readFailure()
        await f.engine.setOptionalAvailability(kind: .ssd, failure: failure)
        #expect(await f.isUnavailable(atMS: 200))
        _ = try await f.accept(ms: 400, values: [60])
        _ = try await f.accept(ms: 600, values: [70])
        #expect(await f.isUnavailable(atMS: 600))
        #expect(await f.engine.rawSamples(for: f.seriesID, nowElapsedNS: 600_000_000).count == 3)
        #expect(await f.engine.emaSamples(for: f.seriesID, nowElapsedNS: 600_000_000).count == 3)
        await f.engine.setOptionalAvailability(kind: .ssd, failure: nil)
        #expect(!(await f.isUnavailable(atMS: 600)))
        #expect(await f.commit.count == 3)
    }
}

private struct GapEngineFixture {
    let engine: MonitorEngine
    let commit: GapCommitProbe
    let seriesID = SeriesID(Fixtures.uuid(101))
    let maximumID = SeriesID(Fixtures.uuid(200))
    static func make(cpuMembers: Int = 1, kind: SensorKind = .cpuZone) throws -> Self {
        let commit = GapCommitProbe()
        let members = (1...cpuMembers).map { SourceID(Fixtures.uuid($0)) }
        var definitions = try members.enumerated().map { index, sourceID in
            SeriesDefinition(seriesID: SeriesID(Fixtures.uuid(101 + index)), metricID: try MetricID(validating: "fixture.zone.\(index)"),
                definitionVersion: 1, kind: kind, displayName: "source \(index)", memberSourceIDs: [sourceID], formula: .identity)
        }
        if cpuMembers > 1 {
            definitions.append(try MetricResolver.makeCPUMaximumDefinition(seriesID: SeriesID(Fixtures.uuid(200)), memberSourceIDs: members))
        }
        let engine = MonitorEngine(clock: TestClock(now: Fixtures.timestamp(ms: 0)), commit: commit,
            session: SessionMetadata(sessionID: SessionID(UUID()), startedWallUnixNS: 1, model: "Mac16,13", osBuild: "24G419", appVersion: "test"),
            configuration: try Configuration.bundledDefaults(), definitions: definitions, cpuPeriodMS: 200)
        return Self(engine: engine, commit: commit)
    }
    @discardableResult func accept(ms: Int64, values: [Double?], periodMS: Int = 200) async throws -> ProcessingReceipt {
        let id = RequestID(UUID())
        let batch = ReadBatch(requestID: id, generation: 1, requestedPeriodMS: periodMS,
            readings: values.enumerated().map { index, value in
                Reading(sourceID: SourceID(Fixtures.uuid(index + 1)), started: Fixtures.timestamp(ms: ms), finished: Fixtures.timestamp(ms: ms),
                    outcome: value.map { .success(valueC: $0, sourceWallUnixNS: nil, freshness: .unknown) } ?? .failure(Self.readFailure()))
            })
        return try await engine.accept(batch, lease: lease(.request(id)))
    }
    func lease(_ owner: PersistenceOwner) -> PersistenceLease {
        PersistenceLease(reservationID: UUID(), owner: owner, generation: 1, maxRecords: 512, maxBytes: 33_554_432)
    }
    func history(atMS: Int64) -> HistoryRequest {
        HistoryRequest(seriesIDs: [seriesID], range: .fiveMinutes, asOfElapsedNS: atMS * 1_000_000, pointLimit: 100)
    }
    func isUnavailable(atMS: Int64) async -> Bool {
        let snapshot = await engine.snapshot(at: Fixtures.timestamp(ms: atMS))
        guard let value = snapshot.values.first else { return false }
        if case .unavailable(capability: .failed, reason: _) = value.state { return true }
        return false
    }
    static func readFailure() -> MonitorFailure {
        MonitorFailure(code: .sensorRead, severity: .degraded, component: "fixture", operation: "read", retryCount: 3,
            sourceID: SourceID(Fixtures.uuid(1)), underlyingCode: "read_failed")
    }
}

private actor GapCommitProbe: PersistenceCommitCapability {
    enum Failure: Error { case failed }
    private var fail = false
    private var reject = false
    private var batches: [PersistenceBatch] = []
    var count: Int { batches.count }
    func failNext() { fail = true }
    func rejectNext() { reject = true }
    func batch(_ id: BatchID) -> PersistenceBatch? { batches.first { $0.batchID == id } }
    func commit(_ batch: PersistenceBatch, using lease: PersistenceLease) async throws -> ProcessingReceipt {
        if fail { fail = false; throw Failure.failed }
        batches.append(batch)
        let mismatch = reject
        reject = false
        return ProcessingReceipt(batchID: mismatch ? BatchID(UUID()) : batch.batchID,
            acceptedRecords: PersistenceBatchMetrics.logicalRecordCount(batch), snapshotGeneration: UInt64(batches.count))
    }
}
