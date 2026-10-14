import Foundation
import Testing
@testable import TemperatureCore

@Suite struct CPUWarningEvaluatorTests {
    @Test func shortSpikeAndBelowThresholdRestartTheCandidate() throws {
        var evaluator = try makeEvaluator()
        evaluator.observe(rawMaxC: 100, at: Fixtures.timestamp(ms: 0), sessionID: session)
        evaluator.observe(rawMaxC: 100, at: Fixtures.timestamp(ms: 4999), sessionID: session)
        #expect(evaluator.snapshot.events.isEmpty)
        evaluator.observe(rawMaxC: 89.99, at: Fixtures.timestamp(ms: 5000), sessionID: session)
        #expect(evaluator.snapshot.state == .monitoring)
        evaluator.observe(rawMaxC: 90, at: Fixtures.timestamp(ms: 6000), sessionID: session)
        evaluator.observe(rawMaxC: 90, at: Fixtures.timestamp(ms: 10999), sessionID: session)
        #expect(evaluator.snapshot.events.isEmpty)
    }

    @Test func inclusiveFiveSecondBoundaryUsesRawPeakAndTriggerTime() throws {
        var evaluator = try makeEvaluator()
        evaluator.observe(rawMaxC: 110, at: Fixtures.timestamp(ms: 0), sessionID: session)
        evaluator.observe(rawMaxC: 90, at: Fixtures.timestamp(ms: 4999), sessionID: session)
        #expect(evaluator.snapshot.state == .pending(since: Fixtures.timestamp(ms: 0)))
        evaluator.observe(rawMaxC: 90, at: Fixtures.timestamp(ms: 5000), sessionID: session)
        let event = try #require(evaluator.snapshot.events.first)
        #expect(event.started == Fixtures.timestamp(ms: 5000))
        #expect(event.peakRawMaxC == 110)
        #expect(event.sessionID == session)
        #expect(evaluator.snapshot.state == .active(eventID: event.eventID))
    }

    @Test func recoveryRequiresTenSecondsAndResetsInsideHysteresisBand() throws {
        var evaluator = try activeEvaluator()
        let id = try #require(evaluator.snapshot.events.first?.eventID)
        evaluator.observe(rawMaxC: 85, at: Fixtures.timestamp(ms: 6000), sessionID: session)
        #expect(evaluator.snapshot.state == .recovering(eventID: id, since: Fixtures.timestamp(ms: 6000)))
        evaluator.observe(rawMaxC: 85, at: Fixtures.timestamp(ms: 15999), sessionID: session)
        #expect(evaluator.snapshot.events.first?.end == .active)
        evaluator.observe(rawMaxC: 85.01, at: Fixtures.timestamp(ms: 16000), sessionID: session)
        #expect(evaluator.snapshot.state == .active(eventID: id))
        evaluator.observe(rawMaxC: 85, at: Fixtures.timestamp(ms: 17000), sessionID: session)
        evaluator.observe(rawMaxC: 85, at: Fixtures.timestamp(ms: 26999), sessionID: session)
        #expect(evaluator.snapshot.events.first?.end == .active)
        evaluator.observe(rawMaxC: 85, at: Fixtures.timestamp(ms: 27000), sessionID: session)
        #expect(evaluator.snapshot.events.first?.end == .ended(at: Fixtures.timestamp(ms: 27000), reason: .recovered))
        #expect(evaluator.snapshot.state == .monitoring)
    }

    @Test func elapsedTimeWinsOverWallClockAndRepeatedOrOlderSamples() throws {
        var evaluator = try makeEvaluator()
        evaluator.observe(rawMaxC: 90, at: Timestamp(elapsedNS: 0, wallUnixNS: 10_000), sessionID: session)
        evaluator.observe(rawMaxC: 0, at: Timestamp(elapsedNS: 0, wallUnixNS: 20_000), sessionID: session)
        evaluator.observe(rawMaxC: 90, at: Timestamp(elapsedNS: 4_999_000_000, wallUnixNS: -10_000), sessionID: session)
        #expect(evaluator.snapshot.events.isEmpty)
        evaluator.observe(rawMaxC: 0, at: Timestamp(elapsedNS: 1, wallUnixNS: 0), sessionID: session)
        evaluator.observe(rawMaxC: 90, at: Timestamp(elapsedNS: 5_000_000_000, wallUnixNS: -20_000), sessionID: session)
        #expect(evaluator.snapshot.events.count == 1)
    }

    @Test(arguments: [CPUWarningInterruptionReason.noData, .readFailure, .gap, .sourceChange, .stale, .lifecycle])
    func interruptionsCloseTheEventAndRequireANewCandidate(reason: CPUWarningInterruptionReason) throws {
        var evaluator = try activeEvaluator()
        let id = try #require(evaluator.snapshot.events.first?.eventID)
        evaluator.interrupt(reason: reason, at: Fixtures.timestamp(ms: 6000))
        #expect(evaluator.snapshot.state == .unableToAssess(reason: reason))
        #expect(evaluator.snapshot.events.first?.end == .ended(at: Fixtures.timestamp(ms: 6000), reason: .interrupted(reason)))
        evaluator.observe(rawMaxC: 90, at: Fixtures.timestamp(ms: 7000), sessionID: session)
        evaluator.observe(rawMaxC: 90, at: Fixtures.timestamp(ms: 11999), sessionID: session)
        #expect(evaluator.snapshot.events.count == 1)
        evaluator.observe(rawMaxC: 90, at: Fixtures.timestamp(ms: 12000), sessionID: session)
        #expect(evaluator.snapshot.events.count == 2)
        #expect(evaluator.snapshot.events.first?.eventID != id)
    }

    @Test func changedRuleAndDisableHaveDistinctEndReasons() throws {
        var evaluator = try activeEvaluator()
        let changed = try CPUWarningRule(enabled: true, thresholdC: 95, durationSeconds: 1, systemNotificationsEnabled: false)
        evaluator.updateRule(changed, at: Fixtures.timestamp(ms: 6000))
        #expect(evaluator.snapshot.events.first?.end == .ended(at: Fixtures.timestamp(ms: 6000), reason: .ruleChanged))
        evaluator.observe(rawMaxC: 95, at: Fixtures.timestamp(ms: 7000), sessionID: session)
        evaluator.observe(rawMaxC: 95, at: Fixtures.timestamp(ms: 8000), sessionID: session)
        let disabled = try CPUWarningRule(enabled: false, thresholdC: 95, durationSeconds: 1, systemNotificationsEnabled: false)
        evaluator.updateRule(disabled, at: Fixtures.timestamp(ms: 9000))
        #expect(evaluator.snapshot.state == .disabled)
        #expect(evaluator.snapshot.events.first?.end == .ended(at: Fixtures.timestamp(ms: 9000), reason: .disabled))
        evaluator.observe(rawMaxC: 120, at: Fixtures.timestamp(ms: 100_000), sessionID: session)
        #expect(evaluator.snapshot.events.count == 2)
    }

    @Test func identicalRulePreservesActiveEventAndRecoveryCandidate() throws {
        var evaluator = try activeEvaluator()
        evaluator.observe(rawMaxC: 85, at: Fixtures.timestamp(ms: 6000), sessionID: session)
        let before = evaluator.snapshot
        evaluator.updateRule(before.rule, at: Fixtures.timestamp(ms: 7000))
        #expect(evaluator.snapshot == before)
        evaluator.observe(rawMaxC: 85, at: Fixtures.timestamp(ms: 16000), sessionID: session)
        #expect(evaluator.snapshot.events.first?.end == .ended(at: Fixtures.timestamp(ms: 16000), reason: .recovered))
    }

    @Test func eventHistoryRetainsFiftyNewestEventsAndUniqueIdentity() throws {
        var evaluator = try makeEvaluator(duration: 1)
        for index in 0..<51 {
            let ms = Int64(index) * 20_000
            evaluator.observe(rawMaxC: 90, at: Fixtures.timestamp(ms: ms), sessionID: session)
            evaluator.observe(rawMaxC: 90, at: Fixtures.timestamp(ms: ms + 1000), sessionID: session)
            evaluator.interrupt(reason: .gap, at: Fixtures.timestamp(ms: ms + 2000))
        }
        #expect(evaluator.snapshot.events.count == 50)
        #expect(Set(evaluator.snapshot.events.map(\.eventID)).count == 50)
        #expect(evaluator.snapshot.events.first?.started.elapsedNS == 1_001_000_000_000)
        #expect(evaluator.snapshot.events.last?.started.elapsedNS == 21_000_000_000)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, 4.99, 120.01])
    func ruleRejectsNonFiniteOrOutsideTemperatureRange(value: Double) {
        #expect(throws: CPUWarningRuleError.thresholdOutOfRange) {
            try CPUWarningRule(enabled: true, thresholdC: value, durationSeconds: 5, systemNotificationsEnabled: false)
        }
    }

    @Test(arguments: [0, 301]) func ruleRejectsOutsideDurationRange(value: Int) {
        #expect(throws: CPUWarningRuleError.durationOutOfRange) {
            try CPUWarningRule(enabled: true, thresholdC: 90, durationSeconds: value, systemNotificationsEnabled: false)
        }
    }

    @Test func ruleDecoderCannotBypassValidation() {
        let invalid = Data(#"{"enabled":true,"thresholdC":121,"durationSeconds":5,"systemNotificationsEnabled":false}"#.utf8)
        #expect(throws: CPUWarningRuleError.thresholdOutOfRange) { try JSONDecoder().decode(CPUWarningRule.self, from: invalid) }
    }

    private var session: SessionID { SessionID(Fixtures.uuid(401)) }
    private func makeEvaluator(duration: Int = 5) throws -> CPUWarningEvaluator {
        let configuration = try Configuration.bundledDefaults()
        return CPUWarningEvaluator(rule: try CPUWarningRule(enabled: true, thresholdC: 90, durationSeconds: duration, systemNotificationsEnabled: false),
            recoveryHysteresisC: configuration.cpuWarning.recoveryHysteresisC,
            recoveryDurationSeconds: configuration.cpuWarning.recoveryDurationSeconds, eventLimit: configuration.cpuWarning.eventLimit)
    }
    private func activeEvaluator() throws -> CPUWarningEvaluator {
        var evaluator = try makeEvaluator()
        evaluator.observe(rawMaxC: 90, at: Fixtures.timestamp(ms: 0), sessionID: session)
        evaluator.observe(rawMaxC: 90, at: Fixtures.timestamp(ms: 5000), sessionID: session)
        return evaluator
    }
}
