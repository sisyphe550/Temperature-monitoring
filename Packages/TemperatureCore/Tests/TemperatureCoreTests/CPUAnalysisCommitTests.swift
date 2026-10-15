import Foundation
import Testing
@testable import TemperatureCore

@Suite struct CPUAnalysisCommitTests {
    @Test func disabledWarningStillAnalyzesCommittedRawRatherThanEMA() async throws {
        let f = try AnalysisEngineFixture()
        try await f.rule(enabled: false)
        _ = try await f.accept(ms: 0, value: 50, periodMS: 200)
        for ms in stride(from: Int64(200), through: 5200, by: 200) { _ = try await f.accept(ms: ms, value: 90, periodMS: 200) }
        let snapshot = await f.snapshot(ms: 5200)
        let current = try available(snapshot.analysis)
        #expect(current.observation.valueC == 90)
        #expect(current.observation.memberSampleIDs.count == 12)
        #expect(current.assessment == .sustained)
        #expect(snapshot.warning.state == .disabled)
        #expect(snapshot.warning.events.isEmpty)
        let maximum = try #require(snapshot.values.first { $0.definition.seriesID == f.maximumID })
        guard case let .available(ema, _, _) = maximum.state else { Issue.record("Missing EMA"); return }
        #expect(ema.valueC < current.observation.valueC)
    }

    @Test func warningAndNotificationSwitchesPreserveAnalysisDuration() async throws {
        let f = try AnalysisEngineFixture()
        for ms in stride(from: Int64(0), through: 2000, by: 1000) { _ = try await f.accept(ms: ms, value: 90) }
        let before = await f.snapshot(ms: 2000).analysis
        try await f.rule(enabled: false, notifications: true)
        #expect(await f.snapshot(ms: 2000).analysis == before)
        for ms in stride(from: Int64(3000), through: 5000, by: 1000) { _ = try await f.accept(ms: ms, value: 90) }
        #expect(try available(await f.snapshot(ms: 5000).analysis).assessment == .sustained)
        try await f.rule(enabled: true, notifications: false)
        #expect(try available(await f.snapshot(ms: 5000).analysis).assessment == .sustained)
        #expect(await f.snapshot(ms: 5000).warning.events.isEmpty)
    }

    @Test(arguments: [(95.0, 5), (90.0, 1)])
    func thresholdOrDurationChangeRequiresFreshObservation(threshold: Double, duration: Int) async throws {
        let f = try AnalysisEngineFixture()
        _ = try await f.accept(ms: 0, value: 90)
        try await f.rule(threshold: threshold, duration: duration)
        let changed = await f.snapshot(ms: 0).analysis
        #expect(changed.thresholdC == threshold)
        #expect(changed.durationSeconds == duration)
        #expect(changed.state == .unavailable(reason: .noData))
        _ = try await f.accept(ms: 1000, value: 90)
        #expect(try available(await f.snapshot(ms: 1000).analysis).assessment == (threshold > 90 ? .belowThreshold : .pending(since: Fixtures.timestamp(ms: 1000))))
    }

    @Test func recoveryUsesCommittedObservationsAndRetainsActivePhaseAboveRecoveryThreshold() async throws {
        let f = try AnalysisEngineFixture()
        try await f.trigger()
        _ = try await f.accept(ms: 6000, value: 89)
        #expect(try available(await f.snapshot(ms: 6000).analysis).assessment == .sustained)
        _ = try await f.accept(ms: 7000, value: 85)
        let recovering = try available(await f.snapshot(ms: 7000).analysis)
        #expect(recovering.assessment == .recovering(since: Fixtures.timestamp(ms: 7000)))
        #expect(try available(await f.snapshot(ms: 10000).analysis).assessment == recovering.assessment)
        for ms in stride(from: Int64(8000), through: 17000, by: 1000) { _ = try await f.accept(ms: ms, value: 85) }
        #expect(try available(await f.snapshot(ms: 17000).analysis).assessment == .belowThreshold)
    }

    @Test(arguments: [50, 100, 200, 500, 1000])
    func samplePeriodTTLHasInclusiveBoundaryAndIgnoresSelectedPeriod(period: Int) async throws {
        let f = try AnalysisEngineFixture()
        _ = try await f.accept(ms: 0, value: 90, periodMS: period)
        await f.engine.setCPUPeriod(milliseconds: period == 1000 ? 50 : 1000)
        let ttl = Int64(max(3 * period, 2000))
        #expect(try available(await f.snapshot(ms: ttl).analysis).assessment == .pending(since: Fixtures.timestamp(ms: 0)))
        #expect(await f.snapshot(ms: ttl + 1).analysis.state == .unavailable(reason: .stale))
    }

    @Test func failedAndIncompleteCPU12CannotReusePreviousRaw() async throws {
        let f = try AnalysisEngineFixture()
        _ = try await f.accept(ms: 0, value: 90)
        var values: [Double?] = Array(repeating: 90, count: 12); values[3] = nil
        _ = try await f.accept(ms: 1000, values: values)
        #expect(await f.snapshot(ms: 1000).analysis.state == .unavailable(reason: .readFailure))
        let id = RequestID(UUID())
        let incomplete = f.batch(ms: 2000, values: Array(repeating: 90, count: 11), id: id)
        _ = try await f.engine.accept(incomplete, lease: f.lease(.request(id)))
        #expect(await f.snapshot(ms: 2000).analysis.state == .unavailable(reason: .noData))
        _ = try await f.accept(ms: 3000, value: 90)
        #expect(try available(await f.snapshot(ms: 3000).analysis).assessment == .pending(since: Fixtures.timestamp(ms: 3000)))
    }

    @Test func rejectedGapLeavesAnalysisWhileCommittedGapAndLifecycleInvalidateIt() async throws {
        let f = try AnalysisEngineFixture()
        _ = try await f.accept(ms: 0, value: 70)
        let before = await f.snapshot(ms: 0).analysis
        let gap = Gap(gapID: GapID(UUID()), seriesID: f.maximumID, startedElapsedNS: 0, endedElapsedNS: nil, reason: .overload)
        await f.commit.rejectNext()
        await #expect(throws: MonitorFailure.self) { try await f.engine.markGap(gap, lease: f.lease(.gap(gap.gapID))) }
        #expect(await f.snapshot(ms: 0).analysis == before)
        _ = try await f.engine.markGap(gap, lease: f.lease(.gap(gap.gapID)))
        #expect(await f.snapshot(ms: 0).analysis.state == .unavailable(reason: .gap))
        let sleeping = try AnalysisEngineFixture()
        _ = try await sleeping.accept(ms: 0, value: 70)
        let gaps = try await sleeping.engine.openSleepGaps(at: Fixtures.timestamp(ms: 1000))
        _ = try await sleeping.engine.commitLifecycleTransition(gaps: gaps, segments: [], lease: sleeping.lease(.gap(GapID(UUID()))))
        #expect(await sleeping.snapshot(ms: 1000).analysis.state == .unavailable(reason: .lifecycle))
    }

    @Test func definitionChangeInvalidatesCurrentAnalysis() async throws {
        let f = try AnalysisEngineFixture()
        _ = try await f.accept(ms: 0, value: 70)
        await f.engine.replaceDefinitions(f.definitions.filter { $0.seriesID != f.maximumID })
        #expect(await f.snapshot(ms: 0).analysis.state == .unavailable(reason: .sourceChange))
    }

    @Test func rejectedAndFailedReceiptsAndReplayDoNotPublishDraftAnalysis() async throws {
        let f = try AnalysisEngineFixture()
        for ms in stride(from: Int64(0), to: 5000, by: 1000) { _ = try await f.accept(ms: ms, value: 90) }
        let before = await f.snapshot(ms: 4000).analysis
        let id = RequestID(UUID()); let batch = f.batch(ms: 5000, values: Array(repeating: 90, count: 12), id: id)
        let lease = f.lease(.request(id)); f.clock.advance(to: Fixtures.timestamp(ms: 5000))
        await f.commit.failNext()
        await #expect(throws: AnalysisCommitProbe.Failure.self) { try await f.engine.accept(batch, lease: lease) }
        #expect(await f.snapshot(ms: 5000).analysis == before)
        await f.commit.rejectNext()
        await #expect(throws: MonitorFailure.self) { try await f.engine.accept(batch, lease: lease) }
        #expect(await f.snapshot(ms: 5000).analysis == before)
        let receipt = try await f.engine.accept(batch, lease: lease)
        let committed = await f.snapshot(ms: 5000).analysis
        #expect(try available(committed).assessment == .sustained)
        #expect(try await f.engine.accept(batch, lease: lease) == receipt)
        #expect(await f.snapshot(ms: 5000).analysis == committed)
    }

    @Test(arguments: [(Int64(3000), true), (Int64(3001), false)])
    func heldReceiptRechecksRawTTLWithWarningDisabled(delay: Int64, valid: Bool) async throws {
        let f = try AnalysisEngineFixture(); try await f.rule(enabled: false)
        for ms in stride(from: Int64(0), to: 5000, by: 1000) { _ = try await f.accept(ms: ms, value: 90) }
        await f.commit.holdNext(); let read = Task { try await f.accept(ms: 5000, value: 90) }
        await f.commit.waitUntilHeld(); f.clock.advance(to: Fixtures.timestamp(ms: 5000 + delay))
        await f.commit.release(); _ = try await read.value
        let result = await f.snapshot(ms: 5000 + delay).analysis
        if valid { #expect(try available(result).assessment == .sustained) }
        else { #expect(result.state == .unavailable(reason: .stale)) }
        #expect(await f.snapshot(ms: 5000 + delay).warning.events.isEmpty)
    }

    @Test func heldReceiptSnapshotIsNonblockingAndRebasesAnalysisIndependentlyOfDisabledWarning() async throws {
        let f = try AnalysisEngineFixture(); try await f.rule(enabled: false); try await f.trigger()
        await f.commit.holdNext(); let read = Task { try await f.accept(ms: 7000, value: 95) }
        await f.commit.waitUntilHeld(); f.clock.advance(to: Fixtures.timestamp(ms: 8100))
        let capture = AnalysisSnapshotCapture()
        let snapshot = Task { await capture.record(await f.snapshot(ms: 8100).analysis) }
        do {
            let deadline = ContinuousClock.now + .milliseconds(250)
            while await capture.value == nil {
                guard ContinuousClock.now < deadline else { throw AnalysisSnapshotCapture.Failure.blockedByCommit }
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(await capture.value?.state == .unavailable(reason: .stale))
            await f.commit.release(); _ = try await read.value; await snapshot.value
            let after = try available(await f.snapshot(ms: 8100).analysis)
            #expect(after.assessment == .pending(since: Fixtures.timestamp(ms: 7000)))
            #expect(await f.snapshot(ms: 8100).warning.events.isEmpty)
        } catch { await f.commit.release(); _ = try? await read.value; await snapshot.value; throw error }
    }

    @Test func trendUsesCommittedEMAAndRawTimestampWithoutRefreshAdvancement() async throws {
        let f = try AnalysisEngineFixture()
        for ms in stride(from: Int64(0), through: 8000, by: 1000) { _ = try await f.accept(ms: ms, value: 50 + Double(ms) / 1000) }
        let first = try available(await f.snapshot(ms: 8000).analysis)
        #expect(first.trend.at == first.observation.timestamp)
        #expect(first.trend.direction == .rising)
        #expect(first.trend.pointCount == 9)
        let emas = await f.engine.emaSamples(for: f.maximumID, nowElapsedNS: 8_000_000_000)
        let expected = TrendCalculator(configuration: try Configuration.bundledDefaults()).compute(seriesID: f.maximumID,
            segment: first.observation.segment, kind: .cpuMain, emaSamples: emas, at: first.observation.timestamp)
        #expect(first.trend == expected)
        #expect(try available(await f.snapshot(ms: 10000).analysis).trend == first.trend)
        #expect(await f.snapshot(ms: 11001).analysis.state == .unavailable(reason: .stale))
    }

    @Test func trendInsufficientBeforeCoverageAndAfterSegmentChange() async throws {
        let f = try AnalysisEngineFixture()
        for ms in stride(from: Int64(0), through: 7000, by: 1000) { _ = try await f.accept(ms: ms, value: 60) }
        #expect(try available(await f.snapshot(ms: 7000).analysis).trend.direction == .insufficient)
        _ = try await f.accept(ms: 8000, value: 60)
        #expect(try available(await f.snapshot(ms: 8000).analysis).trend.direction == .stable)
        let gap = Gap(gapID: GapID(UUID()), seriesID: f.maximumID, startedElapsedNS: 8_000_000_000, endedElapsedNS: 9_000_000_000, reason: .overload)
        _ = try await f.engine.markGap(gap, lease: f.lease(.gap(gap.gapID)))
        _ = try await f.accept(ms: 10000, value: 60)
        let next = try available(await f.snapshot(ms: 10000).analysis)
        #expect(next.observation.segment == 2)
        #expect(next.trend.direction == .insufficient)
        #expect(next.trend.pointCount == 1)
    }

    @Test func sourceChangeWithSameSeriesIDsCannotReuseOldEMATrend() async throws {
        let f = try AnalysisEngineFixture()
        for ms in stride(from: Int64(0), through: 8000, by: 1000) { _ = try await f.accept(ms: ms, value: 60) }
        #expect(try available(await f.snapshot(ms: 8000).analysis).trend.direction == .stable)
        let sources = (1...12).map { Fixtures.source(index: $0, key: $0 == 1 ? "changed-key" : "Tp01") }
        await f.engine.replaceDefinitions(f.definitions, qualifiedSources: sources)
        #expect(await f.snapshot(ms: 8000).analysis.state == .unavailable(reason: .sourceChange))
        _ = try await f.accept(ms: 9000, value: 60)
        let first = try available(await f.snapshot(ms: 9000).analysis)
        #expect(first.trend.direction == .insufficient)
        #expect(first.trend.pointCount == 1)
        for ms in stride(from: Int64(10000), through: 17000, by: 1000) { _ = try await f.accept(ms: ms, value: 60) }
        let current = try available(await f.snapshot(ms: 17000).analysis)
        #expect(current.trend.direction == .stable)
        #expect(current.trend.pointCount == 9)
    }

    @Test func outOfOrderAndOldGenerationCannotReplacePublishedAnalysis() async throws {
        let f = try AnalysisEngineFixture()
        _ = try await f.accept(ms: 1000, value: 90)
        let before = await f.snapshot(ms: 1000).analysis
        _ = try await f.accept(ms: 0, value: 50)
        #expect(await f.snapshot(ms: 1000).analysis == before)
        let id = RequestID(UUID()); let base = f.batch(ms: 2000, values: Array(repeating: 50, count: 12), id: id)
        let old = ReadBatch(requestID: id, generation: 0, requestedPeriodMS: 1000, readings: base.readings)
        let lease = PersistenceLease(reservationID: UUID(), owner: .request(id), generation: 0, maxRecords: 512, maxBytes: 33_554_432)
        await #expect(throws: MonitorFailure.self) { try await f.engine.accept(old, lease: lease) }
        #expect(await f.snapshot(ms: 1000).analysis == before)
    }

    @Test func fewerThanTwelveSourcesHaveNoCPUAssessment() async throws {
        let f = try await ProcessorFixture.make(cpuMembers: 2)
        let id = RequestID(UUID())
        _ = try await f.accept(Fixtures.read(id: id, ms: 0, values: [70, 75], requestedPeriodMS: 1000),
            lease: f.lease(owner: .request(id), generation: 1))
        #expect(await f.engine.snapshot(at: Fixtures.timestamp(ms: 0)).analysis.state == .unavailable(reason: .noData))
    }

    private func available(_ cpu: CPUAnalysisSnapshot) throws -> (observation: Sample, assessment: CPUThresholdAssessment, trend: TrendValue) {
        guard case let .available(observation, assessment, trend) = cpu.state else { throw AnalysisSnapshotCapture.Failure.unavailable }
        return (observation, assessment, trend)
    }
}

private struct AnalysisEngineFixture: Sendable {
    let clock: TestClock
    let engine: MonitorEngine
    let commit: AnalysisCommitProbe
    let definitions: [SeriesDefinition]
    let maximumID = SeriesID(Fixtures.uuid(200))
    init() throws {
        clock = TestClock(now: Fixtures.timestamp(ms: 0))
        commit = AnalysisCommitProbe()
        var definitions = try (1...12).map { try MetricResolver.makeCPUZoneIdentityDefinition(seriesID: SeriesID(Fixtures.uuid(100 + $0)), sourceID: SourceID(Fixtures.uuid($0)), displayName: "CPU \($0)") }
        definitions.append(try MetricResolver.makeCPUMaximumDefinition(seriesID: SeriesID(Fixtures.uuid(200)), memberSourceIDs: (1...12).map { SourceID(Fixtures.uuid($0)) }))
        self.definitions = definitions
        engine = MonitorEngine(clock: clock, commit: commit,
            session: SessionMetadata(sessionID: SessionID(Fixtures.uuid(401)), startedWallUnixNS: 1, model: "Mac16,13", osBuild: "test", appVersion: "test"),
            configuration: try Configuration.bundledDefaults(), definitions: definitions, cpuPeriodMS: 200,
            qualifiedSources: (1...12).map { Fixtures.source(index: $0) })
    }
    func rule(enabled: Bool = true, threshold: Double = 90, duration: Int = 5, notifications: Bool = false) async throws {
        try await engine.setCPUWarningRule(CPUWarningRule(enabled: enabled, thresholdC: threshold, durationSeconds: duration, systemNotificationsEnabled: notifications))
    }
    func lease(_ owner: PersistenceOwner) -> PersistenceLease { PersistenceLease(reservationID: UUID(), owner: owner, generation: 1, maxRecords: 512, maxBytes: 33_554_432) }
    func batch(ms: Int64, values: [Double?], id: RequestID) -> ReadBatch {
        ReadBatch(requestID: id, generation: 1, requestedPeriodMS: 1000, readings: values.enumerated().map { index, value in
            Reading(sourceID: SourceID(Fixtures.uuid(index + 1)), started: Fixtures.timestamp(ms: ms), finished: Fixtures.timestamp(ms: ms),
                outcome: value.map { .success(valueC: $0, sourceWallUnixNS: nil, freshness: .unknown) } ?? .failure(Self.failure()))
        })
    }
    @discardableResult func accept(ms: Int64, value: Double, periodMS: Int = 1000) async throws -> ProcessingReceipt {
        try await accept(ms: ms, values: Array(repeating: value, count: 12), periodMS: periodMS)
    }
    @discardableResult func accept(ms: Int64, values: [Double?], periodMS: Int = 1000) async throws -> ProcessingReceipt {
        clock.advance(to: Fixtures.timestamp(ms: ms))
        let id = RequestID(UUID())
        let base = batch(ms: ms, values: values, id: id)
        let batch = ReadBatch(requestID: id, generation: 1, requestedPeriodMS: periodMS, readings: base.readings)
        return try await engine.accept(batch, lease: lease(.request(id)))
    }
    func snapshot(ms: Int64) async -> Snapshot { await engine.snapshot(at: Fixtures.timestamp(ms: ms)) }
    func trigger() async throws {
        for ms in stride(from: Int64(0), through: 5000, by: 1000) { _ = try await accept(ms: ms, value: 90) }
    }
    static func failure() -> MonitorFailure { MonitorFailure(code: .sensorRead, severity: .degraded, component: "test", operation: "read", retryCount: 0, sourceID: nil, underlyingCode: "failed") }
}

private actor AnalysisCommitProbe: PersistenceCommitCapability {
    enum Failure: Error { case temporaryWrite }
    private var fail = false
    private var reject = false
    private var hold = false
    private var held: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []
    private var count: UInt64 = 0
    func failNext() { fail = true }
    func rejectNext() { reject = true }
    func holdNext() { hold = true }
    func waitUntilHeld() async {
        if held != nil { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func release() { held?.resume(); held = nil }
    func commit(_ batch: PersistenceBatch, using lease: PersistenceLease) async throws -> ProcessingReceipt {
        if hold {
            hold = false
            await withCheckedContinuation { held = $0; observers.forEach { $0.resume() }; observers.removeAll() }
        }
        if fail { fail = false; throw Failure.temporaryWrite }
        count += 1
        let invalid = reject
        reject = false
        return ProcessingReceipt(batchID: invalid ? BatchID(UUID()) : batch.batchID,
            acceptedRecords: PersistenceBatchMetrics.logicalRecordCount(batch), snapshotGeneration: count)
    }
}


private actor AnalysisSnapshotCapture {
    enum Failure: Error { case blockedByCommit, unavailable }
    private(set) var value: CPUAnalysisSnapshot?
    func record(_ value: CPUAnalysisSnapshot) { self.value = value }
}
