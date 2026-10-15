import Foundation

/// Independent always-on analysis. The reused warning events stay private and bounded to one.
struct CPUAnalysisEvaluator {
    private var evaluator: CPUWarningEvaluator
    private(set) var observation: Sample?

    init(rule: CPUWarningRule, recoveryHysteresisC: Double, recoveryDurationSeconds: Int) {
        evaluator = CPUWarningEvaluator(rule: Self.analysisRule(rule), recoveryHysteresisC: recoveryHysteresisC,
            recoveryDurationSeconds: recoveryDurationSeconds, eventLimit: 1)
    }

    var lastObservedAt: Timestamp? { observation?.timestamp }

    mutating func observe(_ sample: Sample, sessionID: SessionID) {
        guard sample.valueC.isFinite else { interrupt(reason: .noData, at: sample.timestamp); return }
        if let last = evaluator.lastObservedAt, sample.timestamp.elapsedNS <= last.elapsedNS { return }
        evaluator.observe(rawMaxC: sample.valueC, at: sample.timestamp, sessionID: sessionID)
        observation = sample
    }

    mutating func interrupt(reason: CPUWarningInterruptionReason, at: Timestamp) {
        evaluator.interrupt(reason: reason, at: at)
        observation = nil
    }

    mutating func updateRule(_ rule: CPUWarningRule, at: Timestamp) {
        let next = Self.analysisRule(rule)
        guard next != evaluator.snapshot.rule else { return }
        evaluator.updateRule(next, at: at)
        // A changed rule is not a new CPU observation.
        interrupt(reason: .noData, at: at)
    }

    func snapshot(trend: TrendValue?) -> CPUAnalysisSnapshot {
        let warning = evaluator.snapshot
        let state: CPUAnalysisState
        if let observation, let trend {
            let assessment: CPUThresholdAssessment
            switch warning.state {
            case .monitoring: assessment = .belowThreshold
            case let .pending(since): assessment = .pending(since: since)
            case .active: assessment = .sustained
            case let .recovering(_, since): assessment = .recovering(since: since)
            case let .unableToAssess(reason):
                return CPUAnalysisSnapshot(thresholdC: warning.rule.thresholdC, durationSeconds: warning.rule.durationSeconds,
                    state: .unavailable(reason: reason))
            case .disabled:
                return CPUAnalysisSnapshot(thresholdC: warning.rule.thresholdC, durationSeconds: warning.rule.durationSeconds,
                    state: .unavailable(reason: .noData))
            }
            state = .available(observation: observation, assessment: assessment, trend: trend)
        } else if case let .unableToAssess(reason) = warning.state {
            state = .unavailable(reason: reason)
        } else {
            state = .unavailable(reason: .noData)
        }
        return CPUAnalysisSnapshot(thresholdC: warning.rule.thresholdC, durationSeconds: warning.rule.durationSeconds, state: state)
    }

    private static func analysisRule(_ rule: CPUWarningRule) -> CPUWarningRule {
        // CPUWarningRule's public initializer already validates threshold and duration.
        try! CPUWarningRule(enabled: true, thresholdC: rule.thresholdC, durationSeconds: rule.durationSeconds,
            systemNotificationsEnabled: false)
    }
}
