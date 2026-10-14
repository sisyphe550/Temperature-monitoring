import Foundation
import Observation
import TemperatureCore

public enum CPUWarningNotificationAuthorization: String, Sendable, Equatable {
    case notRequested, authorized, denied, unavailable
}

public struct CPUWarningNotificationStatus: Sendable, Equatable {
    public let authorization: CPUWarningNotificationAuthorization
    public let lastError: String?
    public init(authorization: CPUWarningNotificationAuthorization, lastError: String?) {
        self.authorization = authorization
        self.lastError = lastError
    }
}

public struct CPUWarningNotificationAttempt: Sendable, Equatable {
    public let sessionID: SessionID
    public let event: CPUWarningEvent
    public let rule: CPUWarningRule
    public let requestedAtElapsedNS: Int64
    public var requestIdentifier: String { "cpu-warning.\(sessionID.rawValue).\(event.eventID.rawValue)" }
}

/// Consumes committed event identities once, including suppressed events. Its
/// bounded ID window plus elapsed high-water mark prevents old event replay.
public struct CPUWarningNotificationPolicy: Sendable {
    private let cooldownNS: Int64
    private let eventLimit: Int
    private var sessionID: SessionID?
    private var running = false
    private var consumedIDs: Set<CPUWarningEventID> = []
    private var consumedOrder: [CPUWarningEventID] = []
    private var consumedThroughElapsedNS: Int64?
    private var lastAttemptElapsedNS: Int64?
    private var lastAttemptEventID: CPUWarningEventID?

    public init(configuration: RuntimeConfiguration) {
        cooldownNS = Int64(configuration.cpuWarning.notificationCooldownSeconds) * 1_000_000_000
        eventLimit = configuration.cpuWarning.eventLimit
    }

    public mutating func start(sessionID: SessionID) {
        if self.sessionID != sessionID {
            consumedIDs.removeAll(keepingCapacity: true)
            consumedOrder.removeAll(keepingCapacity: true)
            consumedThroughElapsedNS = nil
            lastAttemptElapsedNS = nil
            lastAttemptEventID = nil
        }
        self.sessionID = sessionID
        running = true
    }

    public mutating func stop() { running = false }

    public mutating func consume(snapshot: CPUWarningSnapshot, at timestamp: Timestamp) -> CPUWarningNotificationAttempt? {
        guard running, let sessionID else { return nil }
        let priorHighWater = consumedThroughElapsedNS
        let current = Self.activeEvent(in: snapshot)
        let wasConsumed = current.map { consumedIDs.contains($0.eventID) } ?? true
        for event in snapshot.events.prefix(eventLimit) where event.sessionID == sessionID {
            record(event)
        }
        guard let event = current, !wasConsumed, event.sessionID == sessionID,
            priorHighWater.map({ event.started.elapsedNS > $0 }) ?? true,
            snapshot.rule.enabled, snapshot.rule.systemNotificationsEnabled,
            isFresh(event, at: timestamp) else { return nil }
        if let lastAttemptElapsedNS {
            guard timestamp.elapsedNS >= lastAttemptElapsedNS,
                timestamp.elapsedNS - lastAttemptElapsedNS >= cooldownNS else { return nil }
        }
        lastAttemptElapsedNS = timestamp.elapsedNS
        lastAttemptEventID = event.eventID
        return CPUWarningNotificationAttempt(sessionID: sessionID, event: event,
            rule: snapshot.rule, requestedAtElapsedNS: timestamp.elapsedNS)
    }

    public func isCurrent(_ attempt: CPUWarningNotificationAttempt, snapshot: CPUWarningSnapshot, at timestamp: Timestamp) -> Bool {
        guard running, sessionID == attempt.sessionID, snapshot.rule == attempt.rule,
            snapshot.rule.enabled, snapshot.rule.systemNotificationsEnabled,
            let current = Self.activeEvent(in: snapshot), current.eventID == attempt.event.eventID,
            current.sessionID == attempt.sessionID, current.started == attempt.event.started else { return false }
        return isFresh(current, at: timestamp)
    }

    mutating func recordDeliveryStarted(_ attempt: CPUWarningNotificationAttempt, at timestamp: Timestamp) {
        guard running, sessionID == attempt.sessionID, lastAttemptEventID == attempt.event.eventID,
            timestamp.elapsedNS >= lastAttemptElapsedNS ?? 0 else { return }
        // Permission can finish much later than candidate consumption. Cooldown
        // starts when the backend request is actually attempted.
        lastAttemptElapsedNS = timestamp.elapsedNS
    }

    private mutating func record(_ event: CPUWarningEvent) {
        if consumedIDs.insert(event.eventID).inserted { consumedOrder.append(event.eventID) }
        while consumedOrder.count > eventLimit { consumedIDs.remove(consumedOrder.removeFirst()) }
        consumedThroughElapsedNS = max(consumedThroughElapsedNS ?? event.started.elapsedNS, event.started.elapsedNS)
    }

    private func isFresh(_ event: CPUWarningEvent, at timestamp: Timestamp) -> Bool {
        guard event.started.elapsedNS >= 0, timestamp.elapsedNS >= event.started.elapsedNS else { return false }
        return timestamp.elapsedNS - event.started.elapsedNS < cooldownNS
    }

    private static func activeEvent(in snapshot: CPUWarningSnapshot) -> CPUWarningEvent? {
        let eventID: CPUWarningEventID
        switch snapshot.state {
        case .active(let id), .recovering(let id, _): eventID = id
        default: return nil
        }
        return snapshot.events.first { event in
            guard event.eventID == eventID else { return false }
            if case .active = event.end { return true }
            return false
        }
    }
}

@MainActor public protocol CPUWarningNotificationBackend: AnyObject {
    func authorization() async -> CPUWarningNotificationAuthorization
    func requestAuthorization() async throws -> CPUWarningNotificationAuthorization
    func add(_ attempt: CPUWarningNotificationAttempt) async throws
    func cancel(identifier: String)
}

/// Owns permission and delivery tasks; sampling only calls synchronous methods.
/// Backend acceptance is deliberately not exposed as a delivery-success state.
@MainActor @Observable public final class CPUWarningNotificationDispatcher {
    public private(set) var status = CPUWarningNotificationStatus(authorization: .unavailable, lastError: nil)
    @ObservationIgnored private let backend: any CPUWarningNotificationBackend
    @ObservationIgnored private let monotonicElapsedNS: @MainActor () -> Int64
    @ObservationIgnored private var policy: CPUWarningNotificationPolicy
    @ObservationIgnored private var sessionID: SessionID?
    @ObservationIgnored private var running = false
    @ObservationIgnored private var rule: CPUWarningRule?
    @ObservationIgnored private var latestSnapshot: CPUWarningSnapshot?
    @ObservationIgnored private var observedAt: Timestamp?
    @ObservationIgnored private var observationLocalNS: Int64 = 0
    @ObservationIgnored private var permissionTask: Task<Void, Never>?
    @ObservationIgnored private var deliveryTask: Task<Void, Never>?
    @ObservationIgnored private var permissionOrdinal: UInt64 = 0
    @ObservationIgnored private var deliveryOrdinal: UInt64 = 0
    @ObservationIgnored private var requestWanted = false
    @ObservationIgnored private var didRequestAuthorization = false
    @ObservationIgnored private var currentAttempt: CPUWarningNotificationAttempt?

    public init(configuration: RuntimeConfiguration, backend: any CPUWarningNotificationBackend,
        monotonicElapsedNS: (@MainActor () -> Int64)? = nil) {
        self.backend = backend
        policy = CPUWarningNotificationPolicy(configuration: configuration)
        if let monotonicElapsedNS { self.monotonicElapsedNS = monotonicElapsedNS }
        else {
            let clock = SystemClock()
            self.monotonicElapsedNS = { clock.now().elapsedNS }
        }
    }

    public func start(sessionID: SessionID) {
        if self.sessionID != sessionID { cancelDelivery(); latestSnapshot = nil; observedAt = nil }
        self.sessionID = sessionID
        running = true
        policy.start(sessionID: sessionID)
        refreshAuthorization(requestIfNeeded: rule?.systemNotificationsEnabled == true)
    }

    public func update(rule: CPUWarningRule) {
        if self.rule != rule { cancelDelivery() }
        self.rule = rule
        if !rule.systemNotificationsEnabled { requestWanted = false }
        refreshAuthorization(requestIfNeeded: rule.systemNotificationsEnabled)
    }

    public func consume(snapshot: CPUWarningSnapshot, at timestamp: Timestamp) {
        guard running else { return }
        latestSnapshot = snapshot
        observedAt = timestamp
        observationLocalNS = monotonicElapsedNS()
        if let currentAttempt, !isCurrent(currentAttempt) { cancelDelivery() }
        guard let attempt = policy.consume(snapshot: snapshot, at: timestamp), rule == snapshot.rule else { return }
        // Denied/unavailable events are consumed without being queued for a
        // later permission change. Unresolved permission may finish once.
        if status.authorization == .denied { return }
        if status.authorization == .unavailable, permissionTask == nil { return }
        cancelDelivery()
        currentAttempt = attempt
        let ordinal = deliveryOrdinal
        deliveryTask = Task { [weak self] in
            guard let self, !Task.isCancelled, ordinal == deliveryOrdinal, isCurrent(attempt) else { return }
            refreshAuthorization(requestIfNeeded: true)
            await permissionTask?.value
            guard !Task.isCancelled, ordinal == deliveryOrdinal,
                status.authorization == .authorized, isCurrent(attempt) else { return }
            guard let attemptedAt = estimatedTimestamp() else { return }
            policy.recordDeliveryStarted(attempt, at: attemptedAt)
            do {
                try await backend.add(attempt)
                guard !Task.isCancelled, ordinal == deliveryOrdinal, isCurrent(attempt) else {
                    backend.cancel(identifier: attempt.requestIdentifier)
                    return
                }
                status = CPUWarningNotificationStatus(authorization: status.authorization, lastError: nil)
            } catch {
                guard !Task.isCancelled, ordinal == deliveryOrdinal, isCurrent(attempt) else { return }
                status = CPUWarningNotificationStatus(authorization: status.authorization,
                    lastError: "系统通知请求失败：\(error)")
            }
        }
    }

    public func refreshAuthorization() { refreshAuthorization(requestIfNeeded: false) }

    /// Stops notification work while preserving this session's consumed events
    /// and cooldown. Software sleep stops snapshots, so pause is an explicit
    /// invalidation boundary rather than waiting for an interrupted snapshot.
    public func pause() {
        running = false
        policy.stop()
        cancelDelivery()
        permissionOrdinal &+= 1
        permissionTask?.cancel()
        permissionTask = nil
        requestWanted = false
        latestSnapshot = nil
        observedAt = nil
    }

    /// Resumes the same session only after the runtime has resumed sampling.
    /// New committed snapshots establish validity; old attempts stay consumed.
    public func resume() {
        guard !running, let sessionID else { return }
        latestSnapshot = nil
        observedAt = nil
        start(sessionID: sessionID)
    }

    public func stop() {
        pause()
        sessionID = nil
    }

    public func canPresent(requestIdentifier: String) -> Bool {
        guard let currentAttempt, currentAttempt.requestIdentifier == requestIdentifier else { return false }
        return isCurrent(currentAttempt)
    }

    public func canOpenDashboard(requestIdentifier: String) -> Bool {
        guard running, let sessionID else { return false }
        return requestIdentifier.hasPrefix("cpu-warning.\(sessionID.rawValue).")
    }

    private func refreshAuthorization(requestIfNeeded: Bool) {
        requestWanted = requestWanted || requestIfNeeded
        guard permissionTask == nil else { return }
        permissionOrdinal &+= 1
        let ordinal = permissionOrdinal
        permissionTask = Task { [weak self] in
            guard let self else { return }
            defer { if ordinal == permissionOrdinal { permissionTask = nil } }
            let authorization = await backend.authorization()
            guard !Task.isCancelled, ordinal == permissionOrdinal else { return }
            status = CPUWarningNotificationStatus(authorization: authorization, lastError: status.lastError)
            guard authorization == .notRequested, requestWanted, rule?.systemNotificationsEnabled == true,
                !didRequestAuthorization else { return }
            didRequestAuthorization = true
            requestWanted = false
            do {
                let result = try await backend.requestAuthorization()
                guard !Task.isCancelled, ordinal == permissionOrdinal else { return }
                status = CPUWarningNotificationStatus(authorization: result, lastError: nil)
            } catch {
                guard !Task.isCancelled, ordinal == permissionOrdinal else { return }
                status = CPUWarningNotificationStatus(authorization: .unavailable,
                    lastError: "系统通知授权失败：\(error)")
            }
        }
    }

    private func cancelDelivery() {
        deliveryOrdinal &+= 1
        deliveryTask?.cancel()
        deliveryTask = nil
        if let currentAttempt { backend.cancel(identifier: currentAttempt.requestIdentifier) }
        currentAttempt = nil
    }

    private func isCurrent(_ attempt: CPUWarningNotificationAttempt) -> Bool {
        guard running, sessionID == attempt.sessionID, rule == attempt.rule,
            let latestSnapshot, let now = estimatedTimestamp() else { return false }
        return policy.isCurrent(attempt, snapshot: latestSnapshot, at: now)
    }

    private func estimatedTimestamp() -> Timestamp? {
        guard let observedAt else { return nil }
        // Local continuous time is only a delta from the parent's supplied
        // session timestamp; it never substitutes a different elapsed origin.
        let localNow = monotonicElapsedNS()
        let delta = max(0, localNow - observationLocalNS)
        let elapsed = observedAt.elapsedNS.addingReportingOverflow(delta)
        guard !elapsed.overflow else { return nil }
        return Timestamp(elapsedNS: elapsed.partialValue, wallUnixNS: observedAt.wallUnixNS)
    }
}
