import Foundation
import Testing
@testable import TemperatureCore
import TemperaturePresentation
import SensorRuntime

@Suite struct CPUWarningCommitTests {
    @Test func committedCPU12RawMaximumTriggersWhileEMAStillBelowThreshold() async throws {
        let f = try WarningEngineFixture()
        _ = try await f.accept(ms: 0, value: 50, periodMS: 200)
        for ms in stride(from: Int64(200), through: 5200, by: 200) { _ = try await f.accept(ms: ms, value: 90, periodMS: 200) }
        let snapshot = await f.snapshot(ms: 5200)
        #expect(snapshot.warning.events.count == 1)
        #expect(snapshot.warning.events.first?.started.elapsedNS == 5_200_000_000)
        let maximum = try #require(snapshot.values.first { $0.definition.seriesID == f.maximumID })
        guard case let .available(ema, _, _) = maximum.state else { Issue.record("CPU maximum missing"); return }
        #expect(ema.valueC < 90)
        #expect(snapshot.warning.events.first?.peakRawMaxC == 90)
    }

    @Test(arguments: [50, 100, 200, 500, 1000])
    func fiveSamplingPeriodsUseElapsedTimeWithUnknownHardwareTimestamp(periodMS: Int) async throws {
        let f = try WarningEngineFixture()
        try await f.engine.setCPUWarningRule(CPUWarningRule(enabled: true, thresholdC: 90, durationSeconds: 1, systemNotificationsEnabled: false))
        for ms in stride(from: Int64(0), to: 1000, by: periodMS) { _ = try await f.accept(ms: ms, value: 90, periodMS: periodMS) }
        #expect(await f.snapshot(ms: 999).warning.events.isEmpty)
        _ = try await f.accept(ms: 1000, value: 90, periodMS: periodMS)
        #expect(await f.snapshot(ms: 1000).warning.events.first?.started.elapsedNS == 1_000_000_000)
    }

    @Test func periodSwitchPreservesCandidateWithoutUsingSampleCount() async throws {
        let f = try WarningEngineFixture()
        for ms in stride(from: Int64(0), through: 2000, by: 1000) { _ = try await f.accept(ms: ms, value: 90, periodMS: 1000) }
        await f.engine.setCPUPeriod(milliseconds: 50)
        for ms in stride(from: Int64(2050), to: 5000, by: 50) { _ = try await f.accept(ms: ms, value: 90, periodMS: 50) }
        #expect(await f.snapshot(ms: 4999).warning.events.isEmpty)
        _ = try await f.accept(ms: 5000, value: 90, periodMS: 50)
        #expect(await f.snapshot(ms: 5000).warning.events.count == 1)
    }

    @Test func oneFailedMemberInterruptsActiveWarningAndRestartsDuration() async throws {
        let f = try WarningEngineFixture()
        try await f.trigger()
        var values: [Double?] = Array(repeating: 100, count: 12)
        values[4] = nil
        _ = try await f.accept(ms: 6000, values: values)
        let failed = await f.snapshot(ms: 6000).warning
        #expect(failed.state == .unableToAssess(reason: .readFailure))
        #expect(failed.events.first?.end == .ended(at: Fixtures.timestamp(ms: 6000), reason: .interrupted(.readFailure)))
        for ms in stride(from: Int64(7000), to: 12000, by: 1000) { _ = try await f.accept(ms: ms, value: 100) }
        #expect(await f.snapshot(ms: 11999).warning.events.count == 1)
        _ = try await f.accept(ms: 12000, value: 100)
        #expect(await f.snapshot(ms: 12000).warning.events.count == 2)
    }

    @Test func optionalFailuresAndOptionalDefinitionChangesPreserveCPUAccumulator() async throws {
        let f = try WarningEngineFixture()
        _ = try await f.accept(ms: 0, value: 90)
        _ = try await f.accept(ms: 1000, value: 90)
        let ssd = SeriesDefinition(seriesID: SeriesID(Fixtures.uuid(301)), metricID: try MetricID(validating: "storage.ssd"), definitionVersion: 1, kind: .ssd, displayName: "SSD", memberSourceIDs: [SourceID(Fixtures.uuid(21))], formula: .identity)
        await f.engine.replaceDefinitions(f.definitions + [ssd])
        await f.engine.setOptionalAvailability(kind: .ssd, failure: failure())
        let id = RequestID(UUID())
        let batch = ReadBatch(requestID: id, generation: 1, requestedPeriodMS: 500,
            readings: [Reading(sourceID: SourceID(Fixtures.uuid(21)), started: Fixtures.timestamp(ms: 1500), finished: Fixtures.timestamp(ms: 1500), outcome: .failure(failure()))])
        _ = try await f.engine.accept(batch, lease: f.lease(.request(id)))
        for ms in stride(from: Int64(2000), through: 5000, by: 1000) { _ = try await f.accept(ms: ms, value: 90) }
        #expect(await f.snapshot(ms: 5000).warning.events.count == 1)
    }

    @Test func CPUDefinitionChangeEndsEventAndRequiresNewSeriesData() async throws {
        let f = try WarningEngineFixture()
        try await f.trigger()
        var definitions = f.definitions.filter { $0.seriesID != f.maximumID }
        definitions.append(try MetricResolver.makeCPUMaximumDefinition(seriesID: SeriesID(Fixtures.uuid(201)), memberSourceIDs: (1...12).map { SourceID(Fixtures.uuid($0)) }))
        f.clock.advance(to: Fixtures.timestamp(ms: 6000))
        await f.engine.replaceDefinitions(definitions)
        #expect(await f.snapshot(ms: 6000).warning.events.first?.end == .ended(at: Fixtures.timestamp(ms: 6000), reason: .interrupted(.sourceChange)))
        _ = try await f.accept(ms: 6000, value: 90)
        #expect(await f.snapshot(ms: 6000).warning.state == .pending(since: Fixtures.timestamp(ms: 6000)))
    }

    @Test func committedGapAndSleepInterruptButRejectedTransitionDoesNot() async throws {
        let f = try WarningEngineFixture()
        try await f.trigger()
        let gap = Gap(gapID: GapID(UUID()), seriesID: f.maximumID, startedElapsedNS: 6_000_000_000, endedElapsedNS: nil, reason: .overload)
        await f.commit.rejectNext()
        await #expect(throws: MonitorFailure.self) { try await f.engine.markGap(gap, lease: f.lease(.gap(gap.gapID))) }
        #expect(await f.snapshot(ms: 6000).warning.events.first?.end == .active)
        _ = try await f.engine.markGap(gap, lease: f.lease(.gap(gap.gapID)))
        #expect(await f.snapshot(ms: 6000).warning.events.first?.end == .ended(at: Fixtures.timestamp(ms: 6000), reason: .interrupted(.gap)))
        let sleeping = try WarningEngineFixture()
        try await sleeping.trigger()
        let gaps = try await sleeping.engine.openSleepGaps(at: Fixtures.timestamp(ms: 6000))
        _ = try await sleeping.engine.commitLifecycleTransition(gaps: gaps, segments: [], lease: sleeping.lease(.gap(GapID(UUID()))))
        #expect(await sleeping.snapshot(ms: 6000).warning.events.first?.end == .ended(at: Fixtures.timestamp(ms: 6000), reason: .interrupted(.lifecycle)))
    }

    @Test func snapshotRefreshNeverTriggersOrRecoversAndStalenessOnlyInterrupts() async throws {
        let f = try WarningEngineFixture()
        _ = try await f.accept(ms: 0, value: 90, periodMS: 200)
        #expect(await f.snapshot(ms: 2000).warning.events.isEmpty)
        #expect(await f.snapshot(ms: 2001).warning.state == .unableToAssess(reason: .stale))
        let active = try WarningEngineFixture()
        try await active.trigger()
        _ = try await active.accept(ms: 6000, value: 85)
        #expect(await active.snapshot(ms: 9000).warning.events.first?.end == .active)
        #expect(await active.snapshot(ms: 9001).warning.events.first?.end == .ended(at: Fixtures.timestamp(ms: 9001), reason: .interrupted(.stale)))
    }

    @Test func rejectedAndFailedReadCommitDoNotTriggerAndReplayDoesNotDuplicate() async throws {
        let f = try WarningEngineFixture()
        for ms in stride(from: Int64(0), to: 5000, by: 1000) { _ = try await f.accept(ms: ms, value: 90) }
        let id = RequestID(UUID())
        let batch = f.batch(ms: 5000, values: Array(repeating: 90, count: 12), id: id)
        let lease = f.lease(.request(id))
        f.clock.advance(to: Fixtures.timestamp(ms: 5000))
        await f.commit.failNext()
        await #expect(throws: WarningCommitProbe.Failure.self) { try await f.engine.accept(batch, lease: lease) }
        #expect(await f.snapshot(ms: 5000).warning.events.isEmpty)
        await f.commit.rejectNext()
        await #expect(throws: MonitorFailure.self) { try await f.engine.accept(batch, lease: lease) }
        #expect(await f.snapshot(ms: 5000).warning.events.isEmpty)
        let receipt = try await f.engine.accept(batch, lease: lease)
        let once = await f.snapshot(ms: 5000).warning
        #expect(once.events.count == 1)
        #expect(try await f.engine.accept(batch, lease: lease) == receipt)
        #expect(await f.snapshot(ms: 5000).warning == once)
    }

    @Test func ruleChangeWaitsForInFlightCommitAndCannotBeOverwritten() async throws {
        let f = try WarningEngineFixture()
        for ms in stride(from: Int64(0), to: 5000, by: 1000) { _ = try await f.accept(ms: ms, value: 90) }
        f.clock.advance(to: Fixtures.timestamp(ms: 5000))
        await f.commit.holdNext()
        let read = Task { try await f.accept(ms: 5000, value: 90) }
        await f.commit.waitUntilHeld()
        let changed = try CPUWarningRule(enabled: true, thresholdC: 95, durationSeconds: 5, systemNotificationsEnabled: false)
        let update = Task { try await f.engine.setCPUWarningRule(changed) }
        await Task.yield()
        await f.commit.release()
        _ = try await read.value
        try await update.value
        let warning = await f.snapshot(ms: 5000).warning
        #expect(warning.rule == changed)
        #expect(warning.events.count == 1)
        #expect(warning.events.first?.end == .ended(at: Fixtures.timestamp(ms: 5000), reason: .ruleChanged))
        _ = try await f.accept(ms: 6000, value: 90)
        #expect(await f.snapshot(ms: 6000).warning.state == .monitoring)
    }

    @Test func fewerThanTwelveSourcesCannotTriggerWarning() async throws {
        let f = try await ProcessorFixture.make(cpuMembers: 2)
        for ms in stride(from: Int64(0), through: 5000, by: 1000) {
            let id = RequestID(UUID())
            _ = try await f.accept(Fixtures.read(id: id, ms: ms, values: [100, 100], requestedPeriodMS: 1000), lease: f.lease(owner: .request(id), generation: 1))
        }
        #expect(await f.engine.snapshot(at: Fixtures.timestamp(ms: 5000)).warning.events.isEmpty)
    }

    @Test(arguments: [(Int64(3000), true), (Int64(3001), false), (Int64(15000), false)])
    func heldTriggerReceiptRechecksSampleTTLWithoutAnySnapshot(delayMS: Int64, shouldTrigger: Bool) async throws {
        let f = try WarningEngineFixture()
        for ms in stride(from: Int64(0), to: 5000, by: 1000) { _ = try await f.accept(ms: ms, value: 95) }
        await f.commit.holdNext()
        let read = Task { try await f.accept(ms: 5000, value: 95) }
        await f.commit.waitUntilHeld()
        let receiptMS = 5000 + delayMS
        f.clock.advance(to: Fixtures.timestamp(ms: receiptMS))
        // No snapshot observes the held commit; receipt acceptance itself must
        // reject an expired trigger, including when its expiry revision is 0.
        await f.commit.release()
        _ = try await read.value
        let warning = await f.snapshot(ms: receiptMS).warning
        #expect(warning.events.count == (shouldTrigger ? 1 : 0))
        if shouldTrigger {
            #expect(warning.events.first?.started == Fixtures.timestamp(ms: 5000))
            #expect(warning.events.first?.end == .active)
        } else {
            #expect(warning.state == .unableToAssess(reason: .stale))
        }
        #expect(await f.engine.rawSamples(for: f.maximumID, nowElapsedNS: receiptMS * 1_000_000).count == 6)
    }

    @Test func snapshotExpiresCommittedWarningDuringHeldCommitAndReceiptCannotReviveIt() async throws {
        let f = try WarningEngineFixture()
        try await f.trigger()
        let oldEvent = try #require(await f.snapshot(ms: 5000).warning.events.first)
        await f.commit.holdNext()
        let read = Task { try await f.accept(ms: 7000, value: 95) }
        await f.commit.waitUntilHeld()
        f.clock.advance(to: Fixtures.timestamp(ms: 8100))
        let capture = WarningSnapshotCapture()
        let snapshotTask = Task { await capture.record(await f.snapshot(ms: 8100).warning) }
        do {
            let deadline = ContinuousClock.now + .milliseconds(250)
            while await capture.value == nil {
                guard ContinuousClock.now < deadline else { throw WarningSnapshotCapture.Failure.blockedByCommit }
                try await Task.sleep(for: .milliseconds(5))
            }
            let before = try #require(await capture.value)
            #expect(before.state == .unableToAssess(reason: .stale))
            #expect(before.events.first?.end == .ended(at: Fixtures.timestamp(ms: 8100), reason: .interrupted(.stale)))
            await f.commit.release()
            _ = try await read.value
            await snapshotTask.value
            let after = await f.snapshot(ms: 8100).warning
            #expect(after.events.first?.eventID == oldEvent.eventID)
            #expect(after.events.first?.end == .ended(at: Fixtures.timestamp(ms: 8100), reason: .interrupted(.stale)))
            #expect(after.state == .pending(since: Fixtures.timestamp(ms: 7000)))
            #expect(after.events.count == 1)
        } catch {
            await f.commit.release()
            _ = try? await read.value
            await snapshotTask.value
            throw error
        }
    }

    @Test func runtimeRuleActionPublishesTheUpdatedWarningWithoutTemperatureIO() async throws {
        let f = try await ControllerFixture.makeFullCPU()
        let stream = await f.controller.snapshots()
        var iterator = stream.makeAsyncIterator()
        try await f.controller.start()
        let disabled = try CPUWarningRule(enabled: false, thresholdC: 95, durationSeconds: 1, systemNotificationsEnabled: false)
        try await f.controller.setCPUWarningRule(disabled)
        let snapshot = try #require(await iterator.next())
        #expect(snapshot.warning.rule == disabled)
        #expect(snapshot.warning.state == .disabled)
        #expect(snapshot.values.filter { $0.definition.kind == .cpuZone || $0.definition.kind == .cpuMain }
            .allSatisfy { if case .loading = $0.state { return true }; return false })
        await f.controller.stop()
        #expect(await f.controller.lastAcceptFailure() == nil)
    }

    @Test @MainActor func chartRebuildPreservesTheExactWarningBoundary() async throws {
        let f = try WarningEngineFixture()
        try await f.trigger()
        let snapshot = await f.snapshot(ms: 5000)
        _ = try #require(snapshot.warning.events.first)
        let model = PresentationModel(primaryCPUMetricID: try MetricResolver.cpuZoneMaximumMetricID())
        #expect(model.apply(snapshot: snapshot))
        model.beginHistoryLoad()
        try expectWarning(model, equals: snapshot.warning)
        model.apply(history: HistoryResult(layer: .ema, points: [], gaps: [], availableFromElapsedNS: nil, persistedThroughElapsedNS: nil),
            request: HistoryRequest(seriesIDs: [], range: .fiveMinutes, asOfElapsedNS: 5_000_000_000, pointLimit: 100))
        try expectWarning(model, equals: snapshot.warning)
        model.applyHistoryFailure(failure())
        try expectWarning(model, equals: snapshot.warning)
    }

    @MainActor private func expectWarning(_ model: PresentationModel, equals warning: CPUWarningSnapshot) throws {
        guard case let .running(running) = model.state else { Issue.record("Missing running state"); return }
        #expect(running.warning == warning)
    }
    private func failure() -> MonitorFailure { WarningEngineFixture.failure() }
}

private struct WarningEngineFixture: Sendable {
    let clock: TestClock
    let engine: MonitorEngine
    let commit: WarningCommitProbe
    let definitions: [SeriesDefinition]
    let maximumID = SeriesID(Fixtures.uuid(200))
    init() throws {
        clock = TestClock(now: Fixtures.timestamp(ms: 0))
        commit = WarningCommitProbe()
        var definitions = try (1...12).map { try MetricResolver.makeCPUZoneIdentityDefinition(seriesID: SeriesID(Fixtures.uuid(100 + $0)), sourceID: SourceID(Fixtures.uuid($0)), displayName: "CPU \($0)") }
        definitions.append(try MetricResolver.makeCPUMaximumDefinition(seriesID: SeriesID(Fixtures.uuid(200)), memberSourceIDs: (1...12).map { SourceID(Fixtures.uuid($0)) }))
        self.definitions = definitions
        engine = MonitorEngine(clock: clock, commit: commit,
            session: SessionMetadata(sessionID: SessionID(Fixtures.uuid(401)), startedWallUnixNS: 1, model: "Mac16,13", osBuild: "test", appVersion: "test"),
            configuration: try Configuration.bundledDefaults(), definitions: definitions, cpuPeriodMS: 200)
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

private actor WarningCommitProbe: PersistenceCommitCapability {
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

private actor WarningSnapshotCapture {
    enum Failure: Error { case blockedByCommit }
    private(set) var value: CPUWarningSnapshot?
    func record(_ value: CPUWarningSnapshot) { self.value = value }
}
