import Darwin
import Foundation

public struct MachClockBasis: Sendable, Equatable {
    public let originTicks: UInt64
    public let numer: UInt32
    public let denom: UInt32

    public init(originTicks: UInt64, numer: UInt32, denom: UInt32) {
        self.originTicks = originTicks
        self.numer = numer
        self.denom = denom
    }

    public static func current() -> MachClockBasis {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return MachClockBasis(
            originTicks: mach_continuous_time(),
            numer: info.numer,
            denom: info.denom
        )
    }

    public func elapsedNanoseconds(at ticks: UInt64) -> Int64 {
        let delta = ticks >= originTicks ? ticks - originTicks : 0
        return ClockMath.nanoseconds(ticks: delta, numer: numer, denom: denom)
    }
}

public enum ClockMath {
    public static func nanoseconds(ticks: UInt64, numer: UInt32, denom: UInt32) -> Int64 {
        precondition(denom != 0)
        let n = UInt64(numer)
        let d = UInt64(denom)
        let quotient = ticks / d
        let remainder = ticks % d
        let high = quotient.multipliedReportingOverflow(by: n)
        let low = remainder.multipliedReportingOverflow(by: n)
        precondition(!high.overflow && !low.overflow)
        let lowQuotient = low.partialValue / d
        let total = high.partialValue.addingReportingOverflow(lowQuotient)
        precondition(!total.overflow && total.partialValue <= UInt64(Int64.max))
        return Int64(total.partialValue)
    }
}

public struct SystemClock: MonitorClock, Sendable {
    public let basis: MachClockBasis

    public init(basis: MachClockBasis = .current()) {
        self.basis = basis
    }

    public func now() -> Timestamp {
        let elapsed = basis.elapsedNanoseconds(at: mach_continuous_time())
        var time = timespec()
        clock_gettime(CLOCK_REALTIME, &time)
        let wall = Int64(time.tv_sec) &* 1_000_000_000 &+ Int64(time.tv_nsec)
        return Timestamp(elapsedNS: elapsed, wallUnixNS: wall)
    }

    public func sleep(untilElapsedNS: Int64) async throws {
        let remaining = untilElapsedNS - now().elapsedNS
        guard remaining > 0 else { return }
        try await ContinuousClock().sleep(for: .nanoseconds(remaining))
    }
}
