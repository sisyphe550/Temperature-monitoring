import Foundation
import Testing
@testable import TemperatureCore

@Suite struct RetryPolicyTests {
    @Test func sensorBudgetMatchesContract() throws {
        let policy = try RetryPolicy(configuration: Configuration.bundledDefaults())
        #expect(policy.waitsMS(for: .sensor) == [50, 100, 200])
        #expect(policy.additionalAttempts(for: .sensor) == 3)
    }

    @Test func databaseBudgetMatchesContract() throws {
        let policy = try RetryPolicy(configuration: Configuration.bundledDefaults())
        #expect(policy.waitsMS(for: .database) == [100, 250, 500, 1_000, 2_000])
        #expect(policy.additionalAttempts(for: .database) == 5)
    }

    @Test func processingBudgetMatchesContract() throws {
        let policy = try RetryPolicy(configuration: Configuration.bundledDefaults())
        #expect(policy.waitsMS(for: .processing) == [50, 100, 200])
        #expect(policy.additionalAttempts(for: .processing) == 3)
    }

    @Test func uiHistoryBudgetMatchesContract() throws {
        let policy = try RetryPolicy(configuration: Configuration.bundledDefaults())
        #expect(policy.waitsMS(for: .uiHistory) == [100, 250, 500])
        #expect(policy.additionalAttempts(for: .uiHistory) == 3)
    }

    @Test func structuralDatabaseFailuresAreNotRetryable() throws {
        let policy = try RetryPolicy(configuration: Configuration.bundledDefaults())
        let failure = MonitorFailure(
            code: .databaseIntegrity,
            severity: .fatal,
            component: "SessionPersistence",
            operation: "commit",
            retryCount: 0,
            sourceID: nil,
            underlyingCode: "owner_or_generation_mismatch"
        )
        #expect(policy.isRetryable(failure, domain: .database) == false)
    }

    @Test func processingValidateIsNotRetryable() throws {
        let policy = try RetryPolicy(configuration: Configuration.bundledDefaults())
        let failure = MonitorFailure(
            code: .processingValidate,
            severity: .fatal,
            component: "MonitorEngine",
            operation: "accept",
            retryCount: 0,
            sourceID: nil,
            underlyingCode: "non_monotonic_elapsed"
        )
        #expect(policy.isRetryable(failure, domain: .processing) == false)
    }

    @Test func transientDatabaseBusyIsRetryable() throws {
        let policy = try RetryPolicy(configuration: Configuration.bundledDefaults())
        let failure = MonitorFailure(
            code: .databaseOpen,
            severity: .fatal,
            component: "SQLiteStore",
            operation: "open",
            retryCount: 0,
            sourceID: nil,
            underlyingCode: "busy"
        )
        #expect(policy.isRetryable(failure, domain: .database))
    }

    @Test func sensorReadFailureIsRetryable() throws {
        let policy = try RetryPolicy(configuration: Configuration.bundledDefaults())
        let failure = MonitorFailure(
            code: .sensorRead,
            severity: .fatal,
            component: "SamplingService",
            operation: "read",
            retryCount: 0,
            sourceID: nil,
            underlyingCode: "transport_error"
        )
        #expect(policy.isRetryable(failure, domain: .sensor))
    }
}
