import Foundation

/// A value type: callers stage a copy and publish it only after receipt validation.
struct CPUWarningEvaluator {
    private var rule: CPUWarningRule
    private var state: CPUWarningState
    private var events: [CPUWarningEvent] = []
    private let recoveryHysteresisC: Double
    private let recoveryDurationNS: Int64
    private let eventLimit: Int
    private var pendingPeakC: Double?
    private(set) var lastObservedAt: Timestamp?

    init(rule: CPUWarningRule, recoveryHysteresisC: Double, recoveryDurationSeconds: Int, eventLimit: Int) {
        self.rule = rule
        self.recoveryHysteresisC = recoveryHysteresisC
        recoveryDurationNS = Int64(recoveryDurationSeconds) * 1_000_000_000
        self.eventLimit = eventLimit
        state = rule.enabled ? .unableToAssess(reason: .noData) : .disabled
    }

    var snapshot: CPUWarningSnapshot { CPUWarningSnapshot(rule: rule, state: state, events: events) }

    mutating func observe(rawMaxC: Double, at: Timestamp, sessionID: SessionID) {
        guard rule.enabled else { return }
        if let lastObservedAt, at.elapsedNS <= lastObservedAt.elapsedNS { return }
        guard rawMaxC.isFinite else { interrupt(reason: .noData, at: at); return }
        lastObservedAt = at
        if let eventID = activeEventID {
            updateEvent(eventID, peak: rawMaxC)
            if rawMaxC <= rule.thresholdC - recoveryHysteresisC {
                if case let .recovering(_, since) = state {
                    if at.elapsedNS - since.elapsedNS >= recoveryDurationNS {
                        endEvent(at: at, reason: .recovered)
                        state = .monitoring
                    }
                } else {
                    state = .recovering(eventID: eventID, since: at)
                }
            } else {
                state = .active(eventID: eventID)
            }
            return
        }
        guard rawMaxC >= rule.thresholdC else {
            pendingPeakC = nil
            state = .monitoring
            return
        }
        if case let .pending(since) = state {
            pendingPeakC = max(pendingPeakC ?? rawMaxC, rawMaxC)
            if at.elapsedNS - since.elapsedNS >= Int64(rule.durationSeconds) * 1_000_000_000 {
                let event = CPUWarningEvent(eventID: CPUWarningEventID(UUID()), sessionID: sessionID, started: at,
                    thresholdC: rule.thresholdC, durationSeconds: rule.durationSeconds,
                    peakRawMaxC: pendingPeakC ?? rawMaxC, end: .active)
                events.insert(event, at: 0)
                if events.count > eventLimit { events.removeLast(events.count - eventLimit) }
                pendingPeakC = nil
                state = .active(eventID: event.eventID)
            }
        } else {
            pendingPeakC = rawMaxC
            state = .pending(since: at)
        }
    }

    mutating func interrupt(reason: CPUWarningInterruptionReason, at: Timestamp) {
        endEvent(at: at, reason: .interrupted(reason))
        pendingPeakC = nil
        lastObservedAt = nil
        state = rule.enabled ? .unableToAssess(reason: reason) : .disabled
    }

    mutating func updateRule(_ rule: CPUWarningRule, at: Timestamp) {
        guard self.rule != rule else { return }
        endEvent(at: at, reason: rule.enabled ? .ruleChanged : .disabled)
        self.rule = rule
        pendingPeakC = nil
        lastObservedAt = nil
        state = rule.enabled ? .monitoring : .disabled
    }

    private var activeEventID: CPUWarningEventID? {
        switch state {
        case let .active(eventID), let .recovering(eventID, _): eventID
        default: nil
        }
    }

    private mutating func endEvent(at timestamp: Timestamp, reason: CPUWarningEventEndReason) {
        guard let eventID = activeEventID, let index = events.firstIndex(where: { $0.eventID == eventID }) else { return }
        let event = events[index]
        events[index] = CPUWarningEvent(eventID: event.eventID, sessionID: event.sessionID, started: event.started,
            thresholdC: event.thresholdC, durationSeconds: event.durationSeconds, peakRawMaxC: event.peakRawMaxC,
            end: .ended(at: timestamp, reason: reason))
    }

    private mutating func updateEvent(_ eventID: CPUWarningEventID, peak: Double) {
        guard let index = events.firstIndex(where: { $0.eventID == eventID }), peak > events[index].peakRawMaxC else { return }
        let event = events[index]
        events[index] = CPUWarningEvent(eventID: event.eventID, sessionID: event.sessionID, started: event.started,
            thresholdC: event.thresholdC, durationSeconds: event.durationSeconds, peakRawMaxC: peak, end: event.end)
    }
}
