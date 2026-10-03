import Foundation
import Testing
@testable import SensorRuntime
@testable import TemperatureCore

@Suite(.serialized)
struct SuspendedHistoryRegressionTests {
    @Test(arguments: [HistoryRange.fiveMinutes, .oneHour])
    func suspendedHistoryIsCancellationWithoutFailureOrNewReceipt(range: HistoryRange) async throws {
        let fixture = try await ControllerFixture.makeFullCPU()
        try await fixture.controller.start()
        try await fixture.controller.suspendForSleep()
        let batchCount = try await fixture.session.rows(in: "committed_batches")
        let queue = await fixture.controller.persistenceQueueSnapshot()

        await expectCancellation(fixture.controller, request: request(fixture, range: range))

        #expect(await fixture.controller.isSuspended)
        #expect(await fixture.controller.lastAcceptFailure() == nil)
        #expect(await fixture.controller.fatalReportPath() == nil)
        #expect(try await fixture.session.rows(in: "committed_batches") == batchCount)
        #expect(await fixture.controller.persistenceQueueSnapshot() == queue)
        await fixture.controller.stop()
    }

    @Test(arguments: [HistoryRange.fiveMinutes, .oneHour])
    func suspendedHistoryDoesNotDispatchToClosedPersistence(range: HistoryRange) async throws {
        let fixture = try await ControllerFixture.makeFullCPU()
        try await fixture.controller.start()
        try await fixture.controller.suspendForSleep()
        // Any dispatch to SessionPersistence.query now fails session_not_open.
        // Sleep cancellation must happen before either realtime or SQL dispatch.
        try await fixture.session.closeAndDeleteSession()
        await expectCancellation(fixture.controller, request: request(fixture, range: range))
        #expect(await fixture.controller.lastAcceptFailure() == nil)
        await fixture.controller.stop()
    }

    @Test func unstartedAndStoppedHistoryKeepNotRunningFailure() async throws {
        let fixture = try await ControllerFixture.makeFullCPU()
        await expectNotRunning(fixture.controller, request: request(fixture, range: .fiveMinutes))
        try await fixture.controller.start()
        await fixture.controller.stop()
        await expectNotRunning(fixture.controller, request: request(fixture, range: .fiveMinutes))
        await expectNotRunning(fixture.controller, request: request(fixture, range: .oneHour))
    }

    @Test func wakeResumesCommittedSamplingAndClosedSleepGapHistory() async throws {
        let fixture = try await ControllerFixture.makeFullCPU()
        let maxSeriesID = try #require(fixture.cpuMaxSeriesID)
        try await fixture.controller.start()
        fixture.clock.advance(to: Fixtures.timestamp(ms: 200))
        try await waitUntil { await fixture.client.readCount == 1 }
        fixture.clock.advance(to: Fixtures.timestamp(ms: 210))
        await fixture.client.respond(allMembersCelsius: 70)
        try await waitUntil {
            let result = try await fixture.controller.history(request(fixture, range: .fiveMinutes))
            return result.points.contains { $0.elapsedNS == 210_000_000 && $0.valueC == 70 }
        }
        #expect(try await fixture.session.rows(in: "raw_samples") == 13)
        fixture.clock.advance(to: Fixtures.timestamp(ms: 250))
        try await fixture.controller.suspendForSleep()
        await expectCancellation(fixture.controller, request: request(fixture, range: .fiveMinutes))
        await expectCancellation(fixture.controller, request: request(fixture, range: .oneHour))

        fixture.clock.advance(to: Fixtures.timestamp(ms: 5_000))
        try await fixture.controller.resumeAfterWake()
        #expect(!(await fixture.controller.isSuspended))
        // Wait for wake maintenance to finish before entering the next IO slot.
        try await waitUntil { await fixture.controller.persistenceQueueSnapshot().acceptsNewReservations }
        fixture.clock.advance(to: Fixtures.timestamp(ms: 5_200))
        try await waitUntil { await fixture.client.readCount == 2 }
        fixture.clock.advance(to: Fixtures.timestamp(ms: 5_210))
        await fixture.client.respond(allMembersCelsius: 80)
        try await waitUntil {
            let result = try await fixture.controller.history(request(fixture, range: .fiveMinutes))
            return result.points.contains { $0.elapsedNS == 5_210_000_000 && $0.valueC == 80 }
        }

        #expect(try await fixture.session.rows(in: "raw_samples") == 26)
        #expect(try await fixture.session.rows(in: "ema_samples") == 26)
        #expect(await fixture.controller.lastAcceptFailure() == nil)
        #expect(await fixture.controller.fatalReportPath() == nil)
        for range in [HistoryRange.fiveMinutes, .oneHour] {
            let history = try await fixture.controller.history(request(fixture, range: range))
            let gap = try #require(history.gaps.first { $0.seriesID == maxSeriesID && $0.reason == .sleep })
            #expect(gap.startedElapsedNS == 250_000_000)
            #expect(gap.endedElapsedNS == 5_000_000_000)
        }
        let realtime = try await fixture.controller.history(request(fixture, range: .fiveMinutes))
        #expect(realtime.points.filter { $0.seriesID == maxSeriesID }.map(\.segment) == [1, 2])
        await fixture.controller.stop()
    }

    private func request(_ fixture: ControllerFixture, range: HistoryRange) -> HistoryRequest {
        HistoryRequest(seriesIDs: [fixture.cpuMaxSeriesID!], range: range,
            asOfElapsedNS: fixture.clock.now().elapsedNS, pointLimit: 100)
    }

    private func expectCancellation(_ controller: SessionMonitorController, request: HistoryRequest) async {
        do {
            _ = try await controller.history(request)
            Issue.record("A history query during normal sleep must be cancelled")
        } catch is CancellationError {
            // The caller discards this request; it must not enter Fatal.
        } catch {
            Issue.record("Normal sleep returned a failure instead of CancellationError: \(error)")
        }
    }

    private func expectNotRunning(_ controller: SessionMonitorController, request: HistoryRequest) async {
        do {
            _ = try await controller.history(request)
            Issue.record("Unstarted or stopped history must reject not_running")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .processingValidate)
            #expect(failure.severity == .fatal)
            #expect(failure.operation == "history")
            #expect(failure.underlyingCode == "not_running")
        } catch {
            Issue.record("Unexpected not-running history error: \(error)")
        }
    }

    private func waitUntil(_ condition: () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(try await condition()) {
            guard ContinuousClock.now < deadline else {
                Issue.record("Suspended history regression condition timed out")
                throw CocoaError(.fileReadUnknown)
            }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
}
