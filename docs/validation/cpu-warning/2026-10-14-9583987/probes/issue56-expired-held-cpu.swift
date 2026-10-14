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
    var hold = false
    var held: CheckedContinuation<Void, Never>?
    func holdNext() { hold = true }
    func isHeld() -> Bool { held != nil }
    func release() { held?.resume(); held = nil }
    func commit(_ batch: PersistenceBatch, using lease: PersistenceLease) async throws -> ProcessingReceipt {
        if hold { hold = false; await withCheckedContinuation { held = $0 } }
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
        let commit = ProbeCommit()
        let engine = MonitorEngine(clock: clock, commit: commit, session: SessionMetadata(sessionID: session,
            startedWallUnixNS: 0, model: "Mac16,13", osBuild: "probe", appVersion: "probe"),
            configuration: configuration, definitions: definitions, cpuPeriodMS: 1000)
        let rule = try CPUWarningRule(enabled: true, thresholdC: 90, durationSeconds: 5, systemNotificationsEnabled: true)
        try await engine.setCPUWarningRule(rule)
        for seconds in 0...4 {
            clock.t = Int64(seconds)
            let id = RequestID(UUID())
            let readings = sourceIDs.map { Reading(sourceID: $0, started: timestamp(Int64(seconds)), finished: timestamp(Int64(seconds)),
                outcome: .success(valueC: 95, sourceWallUnixNS: nil, freshness: .unknown)) }
            let lease = PersistenceLease(reservationID: UUID(), owner: .request(id), generation: 1, maxRecords: 512, maxBytes: 33_554_432)
            _ = try await engine.accept(ReadBatch(requestID: id, generation: 1, requestedPeriodMS: 1000, readings: readings), lease: lease)
        }
        clock.t = 5
        await commit.holdNext()
        let id = RequestID(UUID())
        let readings = sourceIDs.map { Reading(sourceID: $0, started: timestamp(5), finished: timestamp(5),
            outcome: .success(valueC: 95, sourceWallUnixNS: nil, freshness: .unknown)) }
        let lease = PersistenceLease(reservationID: UUID(), owner: .request(id), generation: 1, maxRecords: 512, maxBytes: 33_554_432)
        let accepting = Task { try await engine.accept(ReadBatch(requestID: id, generation: 1, requestedPeriodMS: 1000, readings: readings), lease: lease) }
        while !(await commit.isHeld()) { await Task.yield() }
        // No snapshot is requested during this held receipt.
        clock.t = 20
        await commit.release()
        _ = try await accepting.value
        let snapshot = await engine.snapshot(at: timestamp(20))
        print("Warning events after an expired CPU triggering sample finally commits:", snapshot.warning.events.count)
        print("State:", snapshot.warning.state)
        print("First event:", snapshot.warning.events.first as Any)
    }
}
