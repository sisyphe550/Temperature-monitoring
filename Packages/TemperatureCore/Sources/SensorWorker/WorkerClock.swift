import Darwin
import Foundation
import TemperatureCore

struct WorkerClock {
    private let basis: MachClockBasis

    init() throws {
        let native = MachClockBasis.current()
        guard let raw = ProcessInfo.processInfo.environment["TEMPERATURE_MONITOR_ORIGIN_TICKS"],
              let origin = UInt64(raw), origin <= native.originTicks else {
            throw WorkerClockError.invalidParentOrigin
        }
        basis = MachClockBasis(originTicks: origin, numer: native.numer, denom: native.denom)
    }

    func timestamp() -> Timestamp {
        let elapsed = basis.elapsedNanoseconds(at: mach_continuous_time())
        var time = timespec()
        clock_gettime(CLOCK_REALTIME, &time)
        let wall = Int64(time.tv_sec) &* 1_000_000_000 &+ Int64(time.tv_nsec)
        return Timestamp(elapsedNS: elapsed, wallUnixNS: wall)
    }
}

enum WorkerClockError: Error { case invalidParentOrigin }
