import Foundation
import Testing
@testable import TemperatureCore
@testable import TemperaturePresentation

@Suite struct CPUWarningNotificationPolicyTests {
    @Test func repeatedSnapshotsAndPermissionChangesCannotReplayOneEvent() throws {
        var policy = CPUWarningNotificationPolicy(configuration: try Configuration.bundledDefaults())
        policy.start(sessionID: warningSession)
        let first = try notificationSnapshot(event: 1, seconds: 5)
        #expect(policy.consume(snapshot: first, at: notificationTime(5))?.event.eventID == CPUWarningEventID(Fixtures.uuid(1)))
        #expect(policy.consume(snapshot: first, at: notificationTime(6)) == nil)
        policy.start(sessionID: warningSession)
        #expect(policy.consume(snapshot: first, at: notificationTime(7)) == nil)
    }

    @Test func disabledNotificationsConsumeTheEventWithoutLaterReplay() throws {
        var policy = CPUWarningNotificationPolicy(configuration: try Configuration.bundledDefaults())
        policy.start(sessionID: warningSession)
        let off = try notificationSnapshot(event: 1, seconds: 5, notifications: false)
        #expect(policy.consume(snapshot: off, at: notificationTime(5)) == nil)
        let on = try notificationSnapshot(event: 1, seconds: 5)
        #expect(policy.consume(snapshot: on, at: notificationTime(6)) == nil)
    }

    @Test func differentEventsRespectElapsedCooldownEvenWhenWallClockJumps() throws {
        var policy = CPUWarningNotificationPolicy(configuration: try Configuration.bundledDefaults())
        policy.start(sessionID: warningSession)
        #expect(policy.consume(snapshot: try notificationSnapshot(event: 1, seconds: 5), at: notificationTime(5)) != nil)
        #expect(policy.consume(snapshot: try notificationSnapshot(event: 2, seconds: 64),
            at: Timestamp(elapsedNS: 64_000_000_000, wallUnixNS: 9_000_000_000)) == nil)
        #expect(policy.consume(snapshot: try notificationSnapshot(event: 3, seconds: 65),
            at: Timestamp(elapsedNS: 65_000_000_000, wallUnixNS: 1)) != nil)
    }

    @Test func lateForeignEndedAndFutureEventsAreSuppressed() throws {
        var policy = CPUWarningNotificationPolicy(configuration: try Configuration.bundledDefaults())
        policy.start(sessionID: warningSession)
        #expect(policy.consume(snapshot: try notificationSnapshot(event: 1, seconds: 5), at: notificationTime(65)) == nil)
        #expect(policy.consume(snapshot: try notificationSnapshot(event: 2, seconds: 66, session: SessionID(Fixtures.uuid(902))), at: notificationTime(66)) == nil)
        #expect(policy.consume(snapshot: try notificationSnapshot(event: 3, seconds: 67,
            end: .ended(at: notificationTime(68), reason: .recovered)), at: notificationTime(68)) == nil)
        #expect(policy.consume(snapshot: try notificationSnapshot(event: 4, seconds: 70), at: notificationTime(69)) == nil)
    }

    @Test func recoveringRemainsCurrentUntilTheEventEndsAndRuleChangesInvalidateAttempts() throws {
        var policy = CPUWarningNotificationPolicy(configuration: try Configuration.bundledDefaults())
        policy.start(sessionID: warningSession)
        let active = try notificationSnapshot(event: 1, seconds: 5)
        let candidate = policy.consume(snapshot: active, at: notificationTime(5))
        let attempt = try #require(candidate)
        let recovering = CPUWarningSnapshot(rule: active.rule,
            state: .recovering(eventID: attempt.event.eventID, since: notificationTime(6)), events: active.events)
        #expect(policy.isCurrent(attempt, snapshot: recovering, at: notificationTime(6)))
        #expect(!policy.isCurrent(attempt, snapshot: try notificationSnapshot(event: 1, seconds: 5, threshold: 91), at: notificationTime(6)))
        #expect(!policy.isCurrent(attempt, snapshot: try notificationSnapshot(event: 1, seconds: 5,
            end: .ended(at: notificationTime(7), reason: .recovered)), at: notificationTime(7)))
        policy.stop()
        #expect(!policy.isCurrent(attempt, snapshot: active, at: notificationTime(7)))
    }

    @Test func evictedOldEventsCannotBeReplayedAfterManyEpisodes() throws {
        var policy = CPUWarningNotificationPolicy(configuration: try Configuration.bundledDefaults())
        policy.start(sessionID: warningSession)
        for event in 1...75 {
            let seconds = Int64(event) * 60
            #expect(policy.consume(snapshot: try notificationSnapshot(event: event, seconds: seconds), at: notificationTime(seconds)) != nil)
        }
        #expect(policy.consume(snapshot: try notificationSnapshot(event: 1, seconds: 60), at: notificationTime(4_560)) == nil)
    }
}

@Suite(.serialized) @MainActor struct CPUWarningNotificationDispatcherTests {
    @Test func denialDoesNotRepeatPromptOrReplayWhenPermissionChanges() async throws {
        let backend = NotificationBoundaryFake()
        backend.authorizationValue = .denied
        let dispatcher = try makeDispatcher(backend)
        let snapshot = try notificationSnapshot(event: 1, seconds: 5)
        dispatcher.update(rule: snapshot.rule)
        dispatcher.start(sessionID: warningSession)
        await waitFor { dispatcher.status.authorization == .denied }
        dispatcher.consume(snapshot: snapshot, at: notificationTime(5))
        await drainTasks()
        #expect(backend.addAttempts.isEmpty)
        #expect(backend.permissionRequestCount == 0)
        backend.authorizationValue = .authorized
        dispatcher.refreshAuthorization()
        await waitFor { dispatcher.status.authorization == .authorized }
        dispatcher.consume(snapshot: snapshot, at: notificationTime(6))
        await drainTasks()
        #expect(backend.addAttempts.isEmpty)
        dispatcher.consume(snapshot: try notificationSnapshot(event: 2, seconds: 65), at: notificationTime(65))
        await waitFor { backend.addAttempts.count == 1 }
        #expect(backend.addAttempts.first?.event.eventID == CPUWarningEventID(Fixtures.uuid(2)))
        dispatcher.stop()
    }

    @Test(arguments: ["recovered", "ruleChanged", "stop"])
    func delayedAuthorizationCannotSendAnInvalidatedEvent(invalidation: String) async throws {
        let backend = NotificationBoundaryFake()
        backend.authorizationValue = .notRequested
        backend.holdPermissionRequest = true
        let dispatcher = try makeDispatcher(backend)
        let snapshot = try notificationSnapshot(event: 1, seconds: 5)
        dispatcher.update(rule: snapshot.rule)
        dispatcher.start(sessionID: warningSession)
        await waitFor { backend.permissionRequestCount == 1 }
        dispatcher.consume(snapshot: snapshot, at: notificationTime(5))
        await drainTasks()
        switch invalidation {
        case "recovered":
            dispatcher.consume(snapshot: try notificationSnapshot(event: 1, seconds: 5,
                end: .ended(at: notificationTime(6), reason: .recovered)), at: notificationTime(6))
        case "ruleChanged": dispatcher.update(rule: try notificationRule(threshold: 91))
        default: dispatcher.stop()
        }
        backend.completePermission(as: .authorized)
        await drainTasks()
        #expect(backend.addAttempts.isEmpty)
        dispatcher.stop()
    }

    @Test func delayedPermissionExpiresUsingMonotonicTimeWithoutAnotherSnapshot() async throws {
        let backend = NotificationBoundaryFake()
        backend.authorizationValue = .notRequested
        backend.holdPermissionRequest = true
        let clock = NotificationElapsedFixture()
        let dispatcher = try makeDispatcher(backend, clock: clock)
        let snapshot = try notificationSnapshot(event: 1, seconds: 5)
        dispatcher.update(rule: snapshot.rule)
        dispatcher.start(sessionID: warningSession)
        await waitFor { backend.permissionRequestCount == 1 }
        dispatcher.consume(snapshot: snapshot, at: notificationTime(5))
        await drainTasks()
        clock.elapsedNS = 60_000_000_000
        backend.completePermission(as: .authorized)
        await drainTasks()
        #expect(backend.addAttempts.isEmpty)
        dispatcher.stop()
    }

    @Test func delayedAuthorizationStartsCooldownAtActualDeliveryAttempt() async throws {
        let backend = NotificationBoundaryFake()
        backend.authorizationValue = .notRequested
        backend.holdPermissionRequest = true
        let clock = NotificationElapsedFixture()
        let dispatcher = try makeDispatcher(backend, clock: clock)
        let snapshot = try notificationSnapshot(event: 1, seconds: 5)
        dispatcher.update(rule: snapshot.rule)
        dispatcher.start(sessionID: warningSession)
        await waitFor { backend.permissionRequestCount == 1 }
        dispatcher.consume(snapshot: snapshot, at: notificationTime(5))
        await drainTasks()
        clock.elapsedNS = 59_000_000_000
        backend.completePermission(as: .authorized)
        await waitFor { backend.addAttempts.count == 1 }
        dispatcher.consume(snapshot: try notificationSnapshot(event: 2, seconds: 65), at: notificationTime(65))
        await drainTasks()
        #expect(backend.addAttempts.count == 1)
        dispatcher.consume(snapshot: try notificationSnapshot(event: 3, seconds: 124), at: notificationTime(124))
        await waitFor { backend.addAttempts.count == 2 }
        #expect(backend.addAttempts.last?.event.eventID == CPUWarningEventID(Fixtures.uuid(3)))
        dispatcher.stop()
    }

    @Test func acceptedRequestIsCanceledIfEventEndsWhileAddIsSuspended() async throws {
        let backend = NotificationBoundaryFake()
        backend.holdAdd = true
        let dispatcher = try makeDispatcher(backend)
        let snapshot = try notificationSnapshot(event: 1, seconds: 5)
        dispatcher.update(rule: snapshot.rule)
        dispatcher.start(sessionID: warningSession)
        await waitFor { dispatcher.status.authorization == .authorized }
        dispatcher.consume(snapshot: snapshot, at: notificationTime(5))
        await waitFor { backend.addAttempts.count == 1 }
        let identifier = try #require(backend.addAttempts.first?.requestIdentifier)
        dispatcher.consume(snapshot: try notificationSnapshot(event: 1, seconds: 5,
            end: .ended(at: notificationTime(6), reason: .recovered)), at: notificationTime(6))
        backend.completeAdd()
        await drainTasks()
        #expect(backend.cancelledIdentifiers.contains(identifier))
        #expect(!dispatcher.canPresent(requestIdentifier: identifier))
        dispatcher.stop()
    }

    @Test func deliveryFailureIsVisibleAndTheEventIsNotRetried() async throws {
        let backend = NotificationBoundaryFake()
        backend.addError = NotificationBoundaryError.deliveryFailed
        let dispatcher = try makeDispatcher(backend)
        let snapshot = try notificationSnapshot(event: 1, seconds: 5)
        dispatcher.update(rule: snapshot.rule)
        dispatcher.start(sessionID: warningSession)
        await waitFor { dispatcher.status.authorization == .authorized }
        dispatcher.consume(snapshot: snapshot, at: notificationTime(5))
        await waitFor { dispatcher.status.lastError != nil }
        #expect(backend.addAttempts.count == 1)
        dispatcher.consume(snapshot: snapshot, at: notificationTime(6))
        dispatcher.refreshAuthorization()
        await drainTasks()
        #expect(backend.addAttempts.count == 1)
        dispatcher.stop()
    }

    @Test func disabledRuleCancelsAnAuthorizationRequestBeforeItStarts() async throws {
        let backend = NotificationBoundaryFake()
        backend.authorizationValue = .notRequested
        let dispatcher = try makeDispatcher(backend)
        dispatcher.update(rule: try notificationRule())
        dispatcher.update(rule: try notificationRule(notifications: false))
        await drainTasks()
        #expect(backend.permissionRequestCount == 0)
        #expect(dispatcher.status.authorization == .notRequested)
        dispatcher.stop()
    }

    @Test func permissionFailureIsVisibleAndNeverEscalatesToDelivery() async throws {
        let backend = NotificationBoundaryFake()
        backend.authorizationValue = .notRequested
        backend.permissionError = NotificationBoundaryError.permissionFailed
        let dispatcher = try makeDispatcher(backend)
        let snapshot = try notificationSnapshot(event: 1, seconds: 5)
        dispatcher.update(rule: snapshot.rule)
        dispatcher.start(sessionID: warningSession)
        await waitFor { dispatcher.status.lastError != nil }
        dispatcher.consume(snapshot: snapshot, at: notificationTime(5))
        await drainTasks()
        #expect(backend.addAttempts.isEmpty)
        #expect(backend.permissionRequestCount == 1)
        dispatcher.stop()
    }

    @Test func committedSoftwareSuspendInvalidatesPendingNotificationWithoutAnotherSnapshot() async throws {
        let fixture = try await ProcessorFixture.make(cpuMembers: 12)
        let rule = try notificationRule()
        try await fixture.engine.setCPUWarningRule(rule)
        for second in 0...5 {
            let request = RequestID(UUID())
            let batch = Fixtures.read(id: request, ms: Int64(second) * 1_000,
                values: Array(repeating: 95.0, count: 12), requestedPeriodMS: 1_000)
            _ = try await fixture.accept(batch, lease: fixture.lease(owner: .request(request), generation: 1))
        }
        let active = await fixture.engine.snapshot(at: Fixtures.timestamp(ms: 5_000))
        let event = try #require(active.warning.events.first)
        #expect(event.end == .active)
        let backend = NotificationBoundaryFake()
        backend.authorizationValue = .notRequested
        backend.holdPermissionRequest = true
        let dispatcher = try makeDispatcher(backend)
        dispatcher.update(rule: rule)
        dispatcher.start(sessionID: fixture.sessionID)
        await waitFor { backend.permissionRequestCount == 1 }
        dispatcher.consume(snapshot: active.warning, at: active.asOf)
        await drainTasks()
        // The App's software-suspend boundary must invalidate pending delivery
        // here before Core stops publishing snapshots.
        dispatcher.pause()
        fixture.clock.advance(to: Fixtures.timestamp(ms: 6_000))
        let gaps = try await fixture.engine.openSleepGaps(at: Fixtures.timestamp(ms: 6_000))
        _ = try await fixture.engine.commitLifecycleTransition(gaps: gaps, segments: [],
            lease: fixture.lease(owner: .gap(GapID(UUID())), generation: 1))
        let interrupted = await fixture.engine.snapshot(at: Fixtures.timestamp(ms: 6_000))
        #expect(interrupted.warning.events.first?.end == .ended(at: Fixtures.timestamp(ms: 6_000),
            reason: .interrupted(.lifecycle)))
        // No interrupted snapshot reaches the App while suspended.
        backend.completePermission(as: .authorized)
        await drainTasks()
        #expect(backend.addAttempts.isEmpty)
        dispatcher.stop()
    }

    @Test func sameSessionResumePreservesCooldownAndConsumedEvents() async throws {
        let backend = NotificationBoundaryFake()
        let dispatcher = try makeDispatcher(backend)
        let first = try notificationSnapshot(event: 1, seconds: 5)
        dispatcher.update(rule: first.rule)
        dispatcher.start(sessionID: warningSession)
        await waitFor { dispatcher.status.authorization == .authorized }
        dispatcher.consume(snapshot: first, at: notificationTime(5))
        await waitFor { backend.addAttempts.count == 1 }
        let identifier = try #require(backend.addAttempts.first?.requestIdentifier)
        dispatcher.pause()
        #expect(!dispatcher.canPresent(requestIdentifier: identifier))
        #expect(!dispatcher.canOpenDashboard(requestIdentifier: identifier))
        dispatcher.resume()
        await drainTasks()
        #expect(!dispatcher.canPresent(requestIdentifier: identifier))
        #expect(backend.addAttempts.count == 1)
        dispatcher.consume(snapshot: first, at: notificationTime(6))
        dispatcher.consume(snapshot: try notificationSnapshot(event: 2, seconds: 64), at: notificationTime(64))
        await drainTasks()
        #expect(backend.addAttempts.count == 1)
        dispatcher.consume(snapshot: try notificationSnapshot(event: 3, seconds: 65), at: notificationTime(65))
        await waitFor { backend.addAttempts.count == 2 }
        #expect(backend.addAttempts.last?.sessionID == warningSession)
        #expect(backend.addAttempts.last?.event.eventID == CPUWarningEventID(Fixtures.uuid(3)))
        dispatcher.stop()
    }

    @Test func lateAuthorizationAfterResumeWaitsForANewCommittedEvent() async throws {
        let backend = NotificationBoundaryFake()
        backend.authorizationValue = .notRequested
        backend.holdPermissionRequest = true
        let dispatcher = try makeDispatcher(backend)
        let first = try notificationSnapshot(event: 1, seconds: 5)
        dispatcher.update(rule: first.rule)
        dispatcher.start(sessionID: warningSession)
        await waitFor { backend.permissionRequestCount == 1 }
        dispatcher.consume(snapshot: first, at: notificationTime(5))
        await drainTasks()
        dispatcher.pause()
        dispatcher.resume()
        backend.completePermission(as: .authorized)
        await drainTasks()
        #expect(backend.addAttempts.isEmpty)
        dispatcher.consume(snapshot: first, at: notificationTime(6))
        await drainTasks()
        #expect(backend.addAttempts.isEmpty)
        dispatcher.consume(snapshot: try notificationSnapshot(event: 2, seconds: 65), at: notificationTime(65))
        await waitFor { backend.addAttempts.count == 1 }
        #expect(backend.permissionRequestCount == 1)
        #expect(backend.addAttempts.first?.event.eventID == CPUWarningEventID(Fixtures.uuid(2)))
        dispatcher.stop()
    }

    @Test func suspendedAddIsCanceledEvenIfItReturnsAfterResume() async throws {
        let backend = NotificationBoundaryFake()
        backend.holdAdd = true
        let dispatcher = try makeDispatcher(backend)
        let first = try notificationSnapshot(event: 1, seconds: 5)
        dispatcher.update(rule: first.rule)
        dispatcher.start(sessionID: warningSession)
        await waitFor { dispatcher.status.authorization == .authorized }
        dispatcher.consume(snapshot: first, at: notificationTime(5))
        await waitFor { backend.addAttempts.count == 1 }
        let identifier = try #require(backend.addAttempts.first?.requestIdentifier)
        dispatcher.pause()
        dispatcher.resume()
        backend.completeAdd()
        await drainTasks()
        #expect(backend.cancelledIdentifiers.contains(identifier))
        #expect(!dispatcher.canPresent(requestIdentifier: identifier))
        #expect(backend.addAttempts.count == 1)
        dispatcher.stop()
    }

    @Test func stopCannotBeResumedWithoutStartingANewSession() async throws {
        let backend = NotificationBoundaryFake()
        let dispatcher = try makeDispatcher(backend)
        let first = try notificationSnapshot(event: 1, seconds: 5)
        dispatcher.update(rule: first.rule)
        dispatcher.start(sessionID: warningSession)
        await waitFor { dispatcher.status.authorization == .authorized }
        dispatcher.stop()
        dispatcher.resume()
        dispatcher.consume(snapshot: first, at: notificationTime(5))
        await drainTasks()
        #expect(backend.addAttempts.isEmpty)
        #expect(!dispatcher.canOpenDashboard(requestIdentifier: "cpu-warning.\(warningSession.rawValue).event"))
    }

    @Test func pauseBeforeQueuedTasksRunCannotStartAPermissionPrompt() async throws {
        let backend = NotificationBoundaryFake()
        backend.authorizationValue = .notRequested
        let dispatcher = try makeDispatcher(backend)
        let first = try notificationSnapshot(event: 1, seconds: 5)
        dispatcher.update(rule: first.rule)
        dispatcher.start(sessionID: warningSession)
        dispatcher.consume(snapshot: first, at: notificationTime(5))
        dispatcher.pause()
        await drainTasks()
        #expect(backend.permissionRequestCount == 0)
        #expect(backend.addAttempts.isEmpty)
        dispatcher.stop()
    }

    @Test func notificationClickCanOnlyOpenTheRunningSession() async throws {
        let backend = NotificationBoundaryFake()
        let dispatcher = try makeDispatcher(backend)
        let snapshot = try notificationSnapshot(event: 1, seconds: 5)
        dispatcher.update(rule: snapshot.rule)
        dispatcher.start(sessionID: warningSession)
        await waitFor { dispatcher.status.authorization == .authorized }
        dispatcher.consume(snapshot: snapshot, at: notificationTime(5))
        await waitFor { backend.addAttempts.count == 1 }
        let identifier = try #require(backend.addAttempts.first?.requestIdentifier)
        #expect(dispatcher.canOpenDashboard(requestIdentifier: identifier))
        #expect(!dispatcher.canOpenDashboard(requestIdentifier: "cpu-warning.foreign.event"))
        dispatcher.stop()
        #expect(!dispatcher.canOpenDashboard(requestIdentifier: identifier))
        dispatcher.start(sessionID: SessionID(Fixtures.uuid(999)))
        #expect(!dispatcher.canOpenDashboard(requestIdentifier: identifier))
        dispatcher.stop()
    }
}

private let warningSession = SessionID(Fixtures.uuid(900))
private func notificationTime(_ seconds: Int64) -> Timestamp {
    Timestamp(elapsedNS: seconds * 1_000_000_000, wallUnixNS: seconds * 1_000_000_000)
}
private func notificationRule(threshold: Double = 90, notifications: Bool = true) throws -> CPUWarningRule {
    try CPUWarningRule(enabled: true, thresholdC: threshold, durationSeconds: 5, systemNotificationsEnabled: notifications)
}
private func notificationSnapshot(event: Int, seconds: Int64, threshold: Double = 90,
    notifications: Bool = true, session: SessionID = warningSession, end: CPUWarningEventEnd = .active) throws -> CPUWarningSnapshot {
    let rule = try notificationRule(threshold: threshold, notifications: notifications)
    let value = CPUWarningEvent(eventID: CPUWarningEventID(Fixtures.uuid(event)), sessionID: session,
        started: notificationTime(seconds), thresholdC: threshold, durationSeconds: 5, peakRawMaxC: 94, end: end)
    let state: CPUWarningState
    if case .active = end { state = .active(eventID: value.eventID) }
    else { state = .monitoring }
    return CPUWarningSnapshot(rule: rule, state: state, events: [value])
}

@MainActor private func makeDispatcher(_ backend: NotificationBoundaryFake,
    clock: NotificationElapsedFixture = NotificationElapsedFixture()) throws -> CPUWarningNotificationDispatcher {
    CPUWarningNotificationDispatcher(configuration: try Configuration.bundledDefaults(), backend: backend,
        monotonicElapsedNS: { clock.elapsedNS })
}
@MainActor private func drainTasks() async { for _ in 0..<100 { await Task.yield() } }
@MainActor private func waitFor(_ predicate: () -> Bool) async {
    for _ in 0..<1_000 {
        if predicate() { return }
        await Task.yield()
    }
    #expect(predicate())
}
@MainActor private final class NotificationElapsedFixture { var elapsedNS: Int64 = 0 }
private enum NotificationBoundaryError: Error { case deliveryFailed, permissionFailed }

@MainActor private final class NotificationBoundaryFake: CPUWarningNotificationBackend {
    var authorizationValue: CPUWarningNotificationAuthorization = .authorized
    var permissionRequestCount = 0
    var addAttempts: [CPUWarningNotificationAttempt] = []
    var cancelledIdentifiers: [String] = []
    var holdPermissionRequest = false
    var holdAdd = false
    var permissionError: Error?
    var addError: Error?
    private var permissionContinuation: CheckedContinuation<CPUWarningNotificationAuthorization, Error>?
    private var addContinuation: CheckedContinuation<Void, Error>?

    func authorization() async -> CPUWarningNotificationAuthorization { authorizationValue }
    func requestAuthorization() async throws -> CPUWarningNotificationAuthorization {
        permissionRequestCount += 1
        if let permissionError { throw permissionError }
        if holdPermissionRequest {
            return try await withCheckedThrowingContinuation { permissionContinuation = $0 }
        }
        authorizationValue = .authorized
        return .authorized
    }
    func add(_ attempt: CPUWarningNotificationAttempt) async throws {
        addAttempts.append(attempt)
        if let addError { throw addError }
        if holdAdd { try await withCheckedThrowingContinuation { addContinuation = $0 } }
    }
    func cancel(identifier: String) { cancelledIdentifiers.append(identifier) }
    func completePermission(as value: CPUWarningNotificationAuthorization) {
        authorizationValue = value
        permissionContinuation?.resume(returning: value)
        permissionContinuation = nil
    }
    func completeAdd() { addContinuation?.resume(); addContinuation = nil }
}
