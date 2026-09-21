import Foundation
@testable import TemperatureCore

public final class TestClock: MonitorClock, @unchecked Sendable {
    private struct Waiter {
        let deadline: Int64
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var current: Timestamp
    private var waiters: [UUID: Waiter] = [:]

    public init(now: Timestamp) {
        self.current = now
    }

    public func now() -> Timestamp {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func sleep(untilElapsedNS: Int64) async throws {
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
            cancel(id)
        }
    }

    public func advance(to timestamp: Timestamp) {
        lock.lock()
        if timestamp.elapsedNS < current.elapsedNS {
            lock.unlock()
            return
        }
        current = Timestamp(elapsedNS: timestamp.elapsedNS, wallUnixNS: timestamp.wallUnixNS)
        let due = waiters.filter { $0.value.deadline <= current.elapsedNS }
        for key in due.keys {
            waiters.removeValue(forKey: key)
        }
        lock.unlock()
        for waiter in due.values {
            waiter.continuation.resume()
        }
    }

    public func cancel(_ id: UUID? = nil) {
        lock.lock()
        let pending: [Waiter]
        if let id, let waiter = waiters.removeValue(forKey: id) {
            pending = [waiter]
        } else if id == nil {
            pending = Array(waiters.values)
            waiters.removeAll()
        } else {
            pending = []
        }
        lock.unlock()
        for waiter in pending {
            waiter.continuation.resume(throwing: CancellationError())
        }
    }
}
