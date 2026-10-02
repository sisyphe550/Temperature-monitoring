import Foundation
import Testing
@testable import SensorRuntime
@testable import TemperatureCore

@Suite(.serialized) struct RequestLifecycleRegressionTests {
    @Test func wakeFirstReadUsesNewRequestIdentity() async throws {
        let fixture = try await ControllerFixture.make()
        try await fixture.run([.init(atMS: 0, event: .start()), .init(atMS: 200, event: .expectRead(kind: .cpu)), .init(atMS: 210, event: .respond(allMembersCelsius: 70))])
        try await fixture.controller.suspendForSleep()
        fixture.clock.advance(to: Fixtures.timestamp(ms: 5000))
        try await fixture.controller.resumeAfterWake()
        // Let the wake watermark finish before advancing into the first IO slot.
        // A manual clock jump can otherwise overlap both full-capacity leases.
        for ms in stride(from: Int64(5000), through: 5800, by: 20) {
            if await fixture.client.readCount >= 2 { break }
            fixture.clock.advance(to: Fixtures.timestamp(ms: ms))
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let readCount = await fixture.client.readCount
        let stats = await fixture.controller.samplingStatistics()
        #expect(readCount == 2, "clock: \(fixture.clock.now().elapsedNS), stats: \(stats)")
        fixture.clock.advance(to: Fixtures.timestamp(ms: max(5300, fixture.clock.now().elapsedNS / 1_000_000 + 100)))
        await fixture.client.respond(allMembersCelsius: 80)
        for _ in 0..<100 {
            if try await fixture.session.rows(in: "raw_samples") == 2 { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let failure = await fixture.controller.lastAcceptFailure()
        let rawCount = try await fixture.session.rows(in: "raw_samples")
        #expect(rawCount == 2, "last failure: \(String(describing: failure))")
        await fixture.controller.stop()
        try await fixture.closeAndDeleteSession()
    }
}
