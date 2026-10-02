import Foundation
import Testing
@testable import TemperatureCore
@testable import SensorRuntime

@Suite(.serialized) struct LongSleepRecoveryRegressionTests {
    @Test func longSleepClosesPreSleepPartialBucketsBeforeWakePrunesRaw() async throws {
        let fixture = try await ControllerFixture.makeFullCPU()
        try await fixture.controller.start()
        fixture.clock.advance(to: Fixtures.timestamp(ms: 200))
        await fixture.client.respond(allMembersCelsius: 70)
        for _ in 0..<200 {
            if try await fixture.session.rows(in: "raw_samples") == 13 { break }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        #expect(try await fixture.session.rows(in: "raw_samples") == 13)
        fixture.clock.advance(to: Fixtures.timestamp(ms: 250))
        try await fixture.controller.suspendForSleep()
        #expect(await fixture.controller.isSuspended)
        fixture.clock.advance(to: Fixtures.timestamp(ms: 500000))
        var wakeFailure: MonitorFailure?
        do { try await fixture.controller.resumeAfterWake() }
        catch let failure as MonitorFailure { wakeFailure = failure }
        #expect(wakeFailure == nil, "A normal 500s sleep must not fail retention because the final pre-sleep second was still open: \(String(describing: wakeFailure))")
        if wakeFailure == nil {
            await fixture.client.respond(allMembersCelsius: 80)
            fixture.clock.advance(to: Fixtures.timestamp(ms: 500200))
            for _ in 0..<200 {
                if try await fixture.session.rows(in: "raw_samples") == 13 { break }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            #expect(try await fixture.session.rows(in: "raw_samples") == 13)
        }
        await fixture.controller.stop()
    }
}
