import Foundation

public enum CPUWarningEventIDTag: Sendable {}
public typealias CPUWarningEventID = TaggedUUID<CPUWarningEventIDTag>

public enum CPUWarningRuleError: Error, Sendable, Equatable {
    case thresholdOutOfRange
    case durationOutOfRange
}

public struct CPUWarningRule: Codable, Sendable, Equatable {
    public let enabled: Bool
    public let thresholdC: Double
    public let durationSeconds: Int
    public let systemNotificationsEnabled: Bool

    public init(enabled: Bool, thresholdC: Double, durationSeconds: Int,
                systemNotificationsEnabled: Bool) throws {
        guard thresholdC.isFinite, (5.0...120.0).contains(thresholdC) else {
            throw CPUWarningRuleError.thresholdOutOfRange
        }
        guard (1...300).contains(durationSeconds) else {
            throw CPUWarningRuleError.durationOutOfRange
        }
        self.enabled = enabled
        self.thresholdC = thresholdC
        self.durationSeconds = durationSeconds
        self.systemNotificationsEnabled = systemNotificationsEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, thresholdC, durationSeconds, systemNotificationsEnabled
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(enabled: values.decode(Bool.self, forKey: .enabled),
                      thresholdC: values.decode(Double.self, forKey: .thresholdC),
                      durationSeconds: values.decode(Int.self, forKey: .durationSeconds),
                      systemNotificationsEnabled: values.decode(Bool.self, forKey: .systemNotificationsEnabled))
    }
}

public enum CPUWarningInterruptionReason: String, Sendable, Equatable {
    case noData, readFailure, gap, sourceChange, stale, lifecycle
}

public enum CPUWarningEventEndReason: Sendable, Equatable {
    case recovered
    case ruleChanged
    case disabled
    case interrupted(CPUWarningInterruptionReason)
}

public enum CPUWarningEventEnd: Sendable, Equatable {
    case active
    case ended(at: Timestamp, reason: CPUWarningEventEndReason)
}

public struct CPUWarningEvent: Sendable, Equatable {
    public let eventID: CPUWarningEventID
    public let sessionID: SessionID
    public let started: Timestamp // Timestamp of the valid sample that establishes the event.
    public let thresholdC: Double
    public let durationSeconds: Int
    public let peakRawMaxC: Double
    public let end: CPUWarningEventEnd

    public init(eventID: CPUWarningEventID, sessionID: SessionID, started: Timestamp,
                thresholdC: Double, durationSeconds: Int, peakRawMaxC: Double,
                end: CPUWarningEventEnd) {
        self.eventID = eventID
        self.sessionID = sessionID
        self.started = started
        self.thresholdC = thresholdC
        self.durationSeconds = durationSeconds
        self.peakRawMaxC = peakRawMaxC
        self.end = end
    }
}

public enum CPUWarningState: Sendable, Equatable {
    case disabled
    case monitoring
    case pending(since: Timestamp)
    case active(eventID: CPUWarningEventID)
    case recovering(eventID: CPUWarningEventID, since: Timestamp)
    case unableToAssess(reason: CPUWarningInterruptionReason)
}

public struct CPUWarningSnapshot: Sendable, Equatable {
    public let rule: CPUWarningRule
    public let state: CPUWarningState
    public let events: [CPUWarningEvent] // Newest first, at most defaults.cpu_warning.event_limit.

    public init(rule: CPUWarningRule, state: CPUWarningState, events: [CPUWarningEvent]) {
        self.rule = rule
        self.state = state
        self.events = events
    }
}

