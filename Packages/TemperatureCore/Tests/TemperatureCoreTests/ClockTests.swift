import Foundation
import Testing
@testable import TemperatureCore

@Suite struct ClockTests {
    @Test func integerTickConversionRoundTripsExactNanoseconds() {
        #expect(ClockMath.nanoseconds(ticks: 1_000_000_000, numer: 1, denom: 1) == 1_000_000_000)
        #expect(ClockMath.nanoseconds(ticks: 3, numer: 125, denom: 3) == 125)
        #expect(ClockMath.nanoseconds(ticks: 9_007_199_254_740_991, numer: 1, denom: 1) == 9_007_199_254_740_991)
    }

    @Test func elapsedContinuesWhenWallClockRewinds() async {
        let clock = TestClock(now: Timestamp(elapsedNS: 10_000_000_000, wallUnixNS: 2_000_000_000_000_000_000))
        clock.advance(
            to: Timestamp(
                elapsedNS: 11_000_000_000,
                wallUnixNS: 2_000_000_000_000_000_000 - 3_600_000_000_000
            )
        )
        let now = clock.now()
        #expect(now.elapsedNS == 11_000_000_000)
        #expect(now.wallUnixNS < 2_000_000_000_000_000_000)
    }

    @Test func concurrentSleepsResumeOnceAndCancelRemovesOneWaiter() async throws {
        let clock = TestClock(now: Timestamp(elapsedNS: 0, wallUnixNS: 0))
        let first = Task { try await clock.sleep(untilElapsedNS: 1_000) }
        let second = Task { try await clock.sleep(untilElapsedNS: 2_000) }
        let third = Task { try await clock.sleep(untilElapsedNS: 3_000) }
        for _ in 0..<20 {
            await Task.yield()
        }
        first.cancel()
        await #expect(throws: CancellationError.self) {
            try await first.value
        }
        clock.advance(to: Timestamp(elapsedNS: 2_000, wallUnixNS: 2_000))
        try await second.value
        clock.advance(to: Timestamp(elapsedNS: 3_000, wallUnixNS: 3_000))
        try await third.value
    }

    @Test func systemClockElapsedIsMonotonicAcrossTwoReads() {
        let clock = SystemClock()
        let first = clock.now()
        let second = clock.now()
        #expect(second.elapsedNS >= first.elapsedNS)
        #expect(first.elapsedNS >= 0)
    }

    @Test func sharedBasisProducesSameOriginForTwoClocks() {
        let basis = MachClockBasis.current()
        let a = SystemClock(basis: basis)
        let b = SystemClock(basis: basis)
        #expect(a.basis == b.basis)
        let delta = abs(a.now().elapsedNS - b.now().elapsedNS)
        #expect(delta < 50_000_000)
    }
}
