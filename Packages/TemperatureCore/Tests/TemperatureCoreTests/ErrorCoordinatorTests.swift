import Foundation
import Testing
@testable import TemperatureCore

@Suite struct ErrorCoordinatorTests {
    @Test func sensorRetriesUseExactWaitSequence() async throws {
        let configuration = try Configuration.bundledDefaults()
        let coordinator = ErrorCoordinator(policy: RetryPolicy(configuration: configuration))
        let failure = transientSensorFailure()
        let context = ErrorEvaluationContext(domain: .sensor, sourceKind: .cpuZone, isRequiredSource: true)

        let first = await coordinator.evaluate(failure: failure, context: context)
        #expect(first == .retry(waitMS: 50, attemptIndex: 0))

        let second = await coordinator.evaluate(failure: failure, context: context)
        #expect(second == .retry(waitMS: 100, attemptIndex: 1))

        let third = await coordinator.evaluate(failure: failure, context: context)
        #expect(third == .retry(waitMS: 200, attemptIndex: 2))

        let exhausted = await coordinator.evaluate(failure: failure, context: context)
        if case let .fatal(result) = exhausted {
            #expect(result.code == .sensorRead)
        } else {
            Issue.record("expected fatal after sensor retry budget exhausted")
        }
    }

    @Test func optionalSensorExhaustionMarksUnavailable() async throws {
        let configuration = try Configuration.bundledDefaults()
        let coordinator = ErrorCoordinator(policy: RetryPolicy(configuration: configuration))
        let failure = transientSensorFailure()
        let context = ErrorEvaluationContext(domain: .sensor, sourceKind: .ssd, isRequiredSource: false)
        let sourceID = SourceID(Fixtures.uuid(601))

        for _ in 0..<3 {
            if case .retry = await coordinator.evaluate(failure: failure, context: context) {
                continue
            }
        }
        let outcome = await coordinator.evaluate(failure: failure, context: context)
        if case let .markUnavailable(result) = outcome {
            #expect(result.code == .sensorRead)
            #expect(result.severity == .degraded)
        } else {
            Issue.record("expected optional source to become unavailable")
        }

        let recovery = await coordinator.evaluateOptionalRecovery(
            sourceID: sourceID,
            readSucceeded: true,
            configuration: configuration
        )
        #expect(recovery == .awaitingConsecutiveSuccesses(successes: 1, required: 3))

        _ = await coordinator.evaluateOptionalRecovery(
            sourceID: sourceID,
            readSucceeded: true,
            configuration: configuration
        )
        let restored = await coordinator.evaluateOptionalRecovery(
            sourceID: sourceID,
            readSucceeded: true,
            configuration: configuration
        )
        #expect(restored == .restored)
        await coordinator.reset(domain: .sensor)
    }

    @Test func nonRetryableFailureEscalatesImmediately() async throws {
        let configuration = try Configuration.bundledDefaults()
        let coordinator = ErrorCoordinator(policy: RetryPolicy(configuration: configuration))
        let failure = MonitorFailure(
            code: .databaseIntegrity,
            severity: .fatal,
            component: "SessionPersistence",
            operation: "commit",
            retryCount: 0,
            sourceID: nil,
            underlyingCode: "duplicate_payload"
        )
        let outcome = await coordinator.evaluate(
            failure: failure,
            context: ErrorEvaluationContext(domain: .database, isRequiredSource: true)
        )
        if case let .fatal(result) = outcome {
            #expect(result.code == .databaseIntegrity)
        } else {
            Issue.record("expected immediate fatal")
        }
        #expect(await coordinator.currentAttemptCount(for: .database) == 0)
    }

    @Test func uiHistoryBudgetIsIndependentFromDatabaseBudget() async throws {
        let configuration = try Configuration.bundledDefaults()
        let coordinator = ErrorCoordinator(policy: RetryPolicy(configuration: configuration))
        let failure = MonitorFailure(
            code: .uiData,
            severity: .fatal,
            component: "HistoryQuery",
            operation: "query",
            retryCount: 0,
            sourceID: nil,
            underlyingCode: "timeout"
        )
        let context = ErrorEvaluationContext(domain: .uiHistory, isRequiredSource: true)

        #expect(await coordinator.evaluate(failure: failure, context: context) == .retry(waitMS: 100, attemptIndex: 0))
        #expect(await coordinator.evaluate(failure: failure, context: context) == .retry(waitMS: 250, attemptIndex: 1))
        #expect(await coordinator.evaluate(failure: failure, context: context) == .retry(waitMS: 500, attemptIndex: 2))
        #expect(await coordinator.currentAttemptCount(for: .database) == 0)
    }

    @Test func successResetsRetryBudget() async throws {
        let configuration = try Configuration.bundledDefaults()
        let coordinator = ErrorCoordinator(policy: RetryPolicy(configuration: configuration))
        let failure = transientSensorFailure()
        let context = ErrorEvaluationContext(domain: .sensor, sourceKind: .cpuZone, isRequiredSource: true)

        _ = await coordinator.evaluate(failure: failure, context: context)
        #expect(await coordinator.currentAttemptCount(for: .sensor) == 1)
        await coordinator.reset(domain: .sensor)
        #expect(await coordinator.currentAttemptCount(for: .sensor) == 0)
    }
}

private func transientSensorFailure() -> MonitorFailure {
    MonitorFailure(
        code: .sensorRead,
        severity: .fatal,
        component: "SamplingService",
        operation: "read",
        retryCount: 0,
        sourceID: nil,
        underlyingCode: "transport_error"
    )
}
