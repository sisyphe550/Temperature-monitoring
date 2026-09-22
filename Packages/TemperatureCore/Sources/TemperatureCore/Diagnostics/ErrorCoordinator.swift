import Foundation

public enum ErrorResolution: Sendable, Equatable {
    case retry(waitMS: Int, attemptIndex: Int)
    case fatal(MonitorFailure)
    case markUnavailable(MonitorFailure)
}

public enum OptionalRecoveryState: Sendable, Equatable {
    case awaitingConsecutiveSuccesses(successes: Int, required: Int)
    case restored
    case exhausted
}

public struct ErrorEvaluationContext: Sendable, Equatable {
    public let domain: RetryDomain
    public let sourceKind: SensorKind?
    public let isRequiredSource: Bool

    public init(
        domain: RetryDomain,
        sourceKind: SensorKind? = nil,
        isRequiredSource: Bool = true
    ) {
        self.domain = domain
        self.sourceKind = sourceKind
        self.isRequiredSource = isRequiredSource
    }
}

public actor ErrorCoordinator {
    private let policy: RetryPolicy
    private var attemptCounts: [RetryDomain: Int] = [:]
    private var optionalRecoveryRounds: [SourceID: Int] = [:]
    private var optionalConsecutiveSuccesses: [SourceID: Int] = [:]

    public init(policy: RetryPolicy) {
        self.policy = policy
    }

    public func evaluate(
        failure: MonitorFailure,
        context: ErrorEvaluationContext
    ) -> ErrorResolution {
        guard policy.isRetryable(failure, domain: context.domain) else {
            return escalateImmediately(failure: failure, context: context)
        }

        let attemptIndex = attemptCounts[context.domain, default: 0]
        if let waitMS = policy.waitMS(for: context.domain, afterFailureIndex: attemptIndex) {
            attemptCounts[context.domain] = attemptIndex + 1
            return .retry(waitMS: waitMS, attemptIndex: attemptIndex)
        }

        return exhausted(failure: failure, context: context)
    }

    public func reset(domain: RetryDomain) {
        attemptCounts[domain] = 0
    }

    public func currentAttemptCount(for domain: RetryDomain) -> Int {
        attemptCounts[domain, default: 0]
    }

    public func evaluateOptionalRecovery(
        sourceID: SourceID,
        readSucceeded: Bool,
        configuration: RuntimeConfiguration
    ) -> OptionalRecoveryState {
        let required = 3
        if readSucceeded {
            let successes = optionalConsecutiveSuccesses[sourceID, default: 0] + 1
            optionalConsecutiveSuccesses[sourceID] = successes
            if successes >= required {
                optionalConsecutiveSuccesses[sourceID] = 0
                optionalRecoveryRounds[sourceID] = 0
                return .restored
            }
            return .awaitingConsecutiveSuccesses(successes: successes, required: required)
        }

        optionalConsecutiveSuccesses[sourceID] = 0
        let round = optionalRecoveryRounds[sourceID, default: 0] + 1
        optionalRecoveryRounds[sourceID] = round
        if round >= configuration.optionalRecoveryAttempts {
            return .exhausted
        }
        return .awaitingConsecutiveSuccesses(successes: 0, required: required)
    }

    private func escalateImmediately(
        failure: MonitorFailure,
        context: ErrorEvaluationContext
    ) -> ErrorResolution {
        if context.domain == .sensor, !context.isRequiredSource {
            return .markUnavailable(
                MonitorFailure(
                    code: failure.code,
                    severity: .degraded,
                    component: failure.component,
                    operation: failure.operation,
                    retryCount: failure.retryCount,
                    sourceID: failure.sourceID,
                    underlyingCode: failure.underlyingCode
                )
            )
        }
        return .fatal(failure)
    }

    private func exhausted(
        failure: MonitorFailure,
        context: ErrorEvaluationContext
    ) -> ErrorResolution {
        if context.domain == .sensor, !context.isRequiredSource {
            return .markUnavailable(
                MonitorFailure(
                    code: failure.code,
                    severity: .degraded,
                    component: failure.component,
                    operation: failure.operation,
                    retryCount: failure.retryCount,
                    sourceID: failure.sourceID,
                    underlyingCode: failure.underlyingCode
                )
            )
        }
        return .fatal(failure)
    }
}
