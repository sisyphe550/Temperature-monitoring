import Foundation
@testable import TemperatureCore

// Test-local task identities distinguish overlapping CPU/publisher/watermark
// deadlines. No production clock/API changes are required.
final class OptionalPhaseClock: MonitorClock, @unchecked Sendable {
    private struct Sleep { let deadline: Int64; let taskHash: Int? }
    private let base: TestClock
    private let lock = NSLock()
    private var sleepers: [UUID: Sleep] = [:]
    private var samplingTaskHash: Int?
    private var snapshotTaskHash: Int?
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
            guard let task = sleepers.values.first(where: { $0.deadline == waitingUntilMS * 1_000_000 })?.taskHash else { return false }
            samplingTaskHash = task
            return true
        }
    }
    func identifySnapshotTask(waitingUntilMS: Int64) -> Bool {
        lock.withLock {
            guard let task = sleepers.values.first(where: { $0.deadline == waitingUntilMS * 1_000_000 && $0.taskHash != samplingTaskHash })?.taskHash else { return false }
            snapshotTaskHash = task
            return true
        }
    }
    func hasSamplingSleep(untilMS: Int64) -> Bool {
        lock.withLock {
            guard let task = samplingTaskHash else { return false }
            return sleepers.values.contains { $0.deadline == untilMS * 1_000_000 && $0.taskHash == task }
        }
    }
    var nextSamplingDeadlineNS: Int64? { nextDeadline(sampling: true) }
    var nextSnapshotDeadlineNS: Int64? { nextDeadline(sampling: false) }
    private func nextDeadline(sampling: Bool) -> Int64? {
        lock.withLock {
            guard let task = sampling ? samplingTaskHash : snapshotTaskHash else { return nil }
            let now = base.now().elapsedNS
            return sleepers.values.filter { $0.taskHash == task && $0.deadline > now }.map(\.deadline).min()
        }
    }
    var sleepDescription: String {
        lock.withLock {
            sleepers.values.sorted { $0.deadline < $1.deadline }.map {
                let role = $0.taskHash == samplingTaskHash ? "sampling" : ($0.taskHash == snapshotTaskHash ? "snapshot" : "other")
                return "\(role):\($0.deadline)"
            }.joined(separator: ",")
        }
    }
}
