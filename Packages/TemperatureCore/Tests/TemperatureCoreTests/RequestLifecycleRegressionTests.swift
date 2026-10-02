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
        fixture.clock.advance(to: Fixtures.timestamp(ms: 5200))
        for _ in 0..<100 {
            if await fixture.client.readCount >= 2 { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(await fixture.client.readCount == 2)
        fixture.clock.advance(to: Fixtures.timestamp(ms: 5300))
        await fixture.client.respond(allMembersCelsius: 80)
        for _ in 0..<100 {
            if try await fixture.session.rows(in: "raw_samples") == 2 { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(try await fixture.session.rows(in: "raw_samples") == 2)
        await fixture.controller.stop()
        try await fixture.closeAndDeleteSession()
    }
}
