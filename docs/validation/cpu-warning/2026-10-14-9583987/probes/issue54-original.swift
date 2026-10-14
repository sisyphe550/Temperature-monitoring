import Foundation
@testable import TemperatureCore
import TemperaturePresentation

final class ProbeClock: MonitorClock, @unchecked Sendable {
    var t: Int64 = 0
    func now() -> Timestamp { timestamp(t) }
    func sleep(untilElapsedNS: Int64) async throws {}
}
func timestamp(_ seconds: Int64) -> Timestamp {
    Timestamp(elapsedNS: seconds * 1_000_000_000, wallUnixNS: seconds * 1_000_000_000)
}
actor ProbeCommit: PersistenceCommitCapability {
    var n: UInt64 = 0
    func commit(_ batch: PersistenceBatch, using lease: PersistenceLease) async throws -> ProcessingReceipt {
        n += 1
        return ProcessingReceipt(batchID: batch.batchID, acceptedRecords: PersistenceBatchMetrics.logicalRecordCount(batch), snapshotGeneration: n)
    }
}
@MainActor final class ProbeBackend: CPUWarningNotificationBackend {
    var continuation: CheckedContinuation<CPUWarningNotificationAuthorization, Error>?
    var requests = 0
    var adds = 0
    func authorization() async -> CPUWarningNotificationAuthorization { .notRequested }
    func requestAuthorization() async throws -> CPUWarningNotificationAuthorization {
        requests += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func add(_ attempt: CPUWarningNotificationAttempt) async throws { adds += 1 }
    func cancel(identifier: String) {}
    func finishAuthorization() { continuation?.resume(returning: .authorized); continuation = nil }
}
@main struct Probe {
    @MainActor static func main() async throws {
        let base = "/Users/sisyphus/.codex/worktrees/cpu-warning/Temperature monitoring"
        let configuration = try Configuration.load(from: URL(fileURLWithPath: base + "/docs/contracts/defaults-v1.json"))
        let clock = ProbeClock()
        let session = SessionID(UUID())
        let sourceIDs = (0..<12).map { _ in SourceID(UUID()) }
        var definitions: [SeriesDefinition] = try sourceIDs.enumerated().map { i, source in
            try MetricResolver.makeCPUZoneIdentityDefinition(seriesID: SeriesID(UUID()), sourceID: source, displayName: "CPU \(i)")
        }
        let maximumID = SeriesID(UUID())
        definitions.append(try MetricResolver.makeCPUMaximumDefinition(seriesID: maximumID, memberSourceIDs: sourceIDs))
        let engine = MonitorEngine(clock: clock, commit: ProbeCommit(), session: SessionMetadata(sessionID: session,
            startedWallUnixNS: 0, model: "Mac16,13", osBuild: "probe", appVersion: "probe"),
            configuration: configuration, definitions: definitions, cpuPeriodMS: 1000)
        let rule = try CPUWarningRule(enabled: true, thresholdC: 90, durationSeconds: 5, systemNotificationsEnabled: true)
        try await engine.setCPUWarningRule(rule)
        for seconds in 0...5 {
            clock.t = Int64(seconds)
            let id = RequestID(UUID())
            let readings = sourceIDs.map { Reading(sourceID: $0, started: timestamp(Int64(seconds)), finished: timestamp(Int64(seconds)),
                outcome: .success(valueC: 95, sourceWallUnixNS: nil, freshness: .unknown)) }
            let lease = PersistenceLease(reservationID: UUID(), owner: .request(id), generation: 1, maxRecords: 512, maxBytes: 33_554_432)
            _ = try await engine.accept(ReadBatch(requestID: id, generation: 1, requestedPeriodMS: 1000, readings: readings), lease: lease)
        }
        let active = await engine.snapshot(at: timestamp(5))
        let backend = ProbeBackend()
        let dispatcher = CPUWarningNotificationDispatcher(configuration: configuration, backend: backend, monotonicElapsedNS: { 0 })
        dispatcher.update(rule: rule)
        dispatcher.start(sessionID: session)
        for _ in 0..<200 { await Task.yield() }
        dispatcher.consume(snapshot: active.warning, at: active.asOf)
        for _ in 0..<200 { await Task.yield() }
        // SessionMonitorController.suspendForSleep stops snapshot publication
        // before this committed transition, leaving App dispatcher unchanged.
        clock.t = 6
        let gaps = try await engine.openSleepGaps(at: timestamp(6))
        let lease = PersistenceLease(reservationID: UUID(), owner: .gap(GapID(UUID())), generation: 1, maxRecords: 512, maxBytes: 33_554_432)
        _ = try await engine.commitLifecycleTransition(gaps: gaps, segments: [], lease: lease)
        let interrupted = await engine.snapshot(at: timestamp(6))
        print("Engine warning after sleep:", interrupted.warning.state)
        print("Engine event end:", interrupted.warning.events[0].end)
        backend.finishAuthorization()
        for _ in 0..<500 { await Task.yield() }
        print("Notification adds after committed sleep interruption:", backend.adds)
        guard backend.adds == 1 else { fatalError("Expected current missing lifecycle propagation") }
        dispatcher.stop()
    }
}
