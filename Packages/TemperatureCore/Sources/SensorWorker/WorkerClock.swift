import Darwin
import Foundation
import TemperatureCore

struct WorkerClock {
    private let basis: MachClockBasis

    init() {
        basis = MachClockBasis.current()
    }

    func timestamp() -> Timestamp {
        let elapsed = basis.elapsedNanoseconds(at: mach_continuous_time())
        var time = timespec()
        clock_gettime(CLOCK_REALTIME, &time)
        let wall = Int64(time.tv_sec) &* 1_000_000_000 &+ Int64(time.tv_nsec)
        return Timestamp(elapsedNS: elapsed, wallUnixNS: wall)
    }
}
