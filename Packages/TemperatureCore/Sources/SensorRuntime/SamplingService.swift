import Foundation
import TemperatureCore

public enum SamplingScheduleKind: Int, Sendable, Comparable, CaseIterable {
    case cpu = 0
    case ssd = 1
    case battery = 2

    public static func < (lhs: SamplingScheduleKind, rhs: SamplingScheduleKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct SamplingStatistics: Sendable, Equatable {
    public var skippedByKind: [SamplingScheduleKind: Int]
    public var completedReads: Int

    public init(skippedByKind: [SamplingScheduleKind: Int] = [:], completedReads: Int = 0) {
        self.skippedByKind = skippedByKind
        self.completedReads = completedReads
    }
}

public struct SamplingReadEvent: Sendable, Equatable {
    public let kind: SamplingScheduleKind
    public let plannedElapsedNS: Int64
    public let requestID: RequestID
    public let requestedPeriodMS: Int
    public let lease: PersistenceLease
    public let batch: ReadBatch

    public init(
        kind: SamplingScheduleKind,
        plannedElapsedNS: Int64,
        requestID: RequestID,
        requestedPeriodMS: Int,
        lease: PersistenceLease,
        batch: ReadBatch
    ) {
        self.kind = kind
        self.plannedElapsedNS = plannedElapsedNS
        self.requestID = requestID
        self.requestedPeriodMS = requestedPeriodMS
        self.lease = lease
        self.batch = batch
    }
}

enum SchedulePlanner {
    static func advanceAfterPlannedRead(
        plannedDueElapsedNS: Int64,
        periodMS: Int,
        nowElapsedNS: Int64
    ) -> (nextDueElapsedNS: Int64, skipped: Int) {
        let periodNS = Int64(periodMS) * 1_000_000
        var next = plannedDueElapsedNS + periodNS
        var skipped = 0
        while next <= nowElapsedNS {
            skipped += 1
            next += periodNS
        }
        return (next, skipped)
    }

    static func skipOverdue(
        nextDueElapsedNS: Int64,
        periodMS: Int,
        nowElapsedNS: Int64
    ) -> (nextDueElapsedNS: Int64, skipped: Int) {
        var next = nextDueElapsedNS
        var skipped = 0
        while next < nowElapsedNS {
            skipped += 1
            next += periodNS(periodMS)
        }
        return (next, skipped)
    }

    private static func periodNS(_ periodMS: Int) -> Int64 {
        Int64(periodMS) * 1_000_000
    }
}

struct ScheduleState: Equatable {
    var kind: SamplingScheduleKind
    var periodMS: Int
    var nextDueElapsedNS: Int64
    var sourceIDs: [SourceID]
}

public actor SamplingService {
    public typealias ReadHandler = @Sendable (SamplingReadEvent) async -> Void
    public typealias WillReadHandler = @Sendable (RequestID, Int64) async -> Void

    private let clock: MonitorClock
    private let client: any SensorClient
    private let reservation: PersistenceReservationCapability
    private let configuration: RuntimeConfiguration
    private var schedules: [SamplingScheduleKind: ScheduleState] = [:]
    private var cpuPeriodMS: Int
    private var catalogGeneration: UInt64?
    private var running = false
    private var loopTask: Task<Void, Never>?
    private var onRead: ReadHandler?
    private var willRead: WillReadHandler?
    private var stats = SamplingStatistics()
    private var didFinishRead: WillReadHandler?
    private var readInFlight = false

    public init(
        clock: MonitorClock,
        client: any SensorClient,
        reservation: PersistenceReservationCapability,
        configuration: RuntimeConfiguration
    ) {
        self.clock = clock
        self.client = client
        self.reservation = reservation
        self.configuration = configuration
        cpuPeriodMS = configuration.cpuDefaultMS
    }

    public func start(
        catalog: QualifiedSourceCatalog,
        willRead: WillReadHandler? = nil,
        didFinishRead: WillReadHandler? = nil,
        onRead: @escaping ReadHandler
    ) async {
        await stop()
        schedules = Self.makeSchedules(
            catalog: catalog,
            cpuPeriodMS: cpuPeriodMS,
            ssdIntervalMS: configuration.ssdIntervalMS,
            batteryIntervalMS: configuration.batteryIntervalMS,
            startElapsedNS: clock.now().elapsedNS
        )
        catalogGeneration = catalog.generation
        stats = SamplingStatistics()
        self.willRead = willRead
        self.didFinishRead = didFinishRead
        self.onRead = onRead
        running = true
        loopTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    public func setCPUPeriod(milliseconds: Int) {
        cpuPeriodMS = milliseconds
        guard var cpu = schedules[.cpu] else {
            return
        }
        cpu.periodMS = milliseconds
        cpu.nextDueElapsedNS = clock.now().elapsedNS + Int64(milliseconds) * 1_000_000
        schedules[.cpu] = cpu
    }

    public func stop() async {
        running = false
        let task = loopTask
        loopTask = nil
        task?.cancel()
        await task?.value
        onRead = nil
        willRead = nil
        didFinishRead = nil
        catalogGeneration = nil
        schedules = [:]
    }

    public func statistics() -> SamplingStatistics {
        stats
    }

    public func nextDueElapsedNS(for kind: SamplingScheduleKind) -> Int64? {
        schedules[kind]?.nextDueElapsedNS
    }

    public var isReadInFlight: Bool {
        readInFlight
    }

    private func runLoop() async {
        while running {
            let now = clock.now().elapsedNS
            while running, let kind = dueScheduleKind(at: clock.now().elapsedNS) {
                let plannedDue = schedules[kind]!.nextDueElapsedNS
                await executeRead(for: kind, plannedDueElapsedNS: plannedDue)
            }
            guard running else {
                break
            }
            let refreshedNow = clock.now().elapsedNS
            if dueScheduleKind(at: refreshedNow) != nil {
                continue
            }

            guard let wakeElapsedNS = schedules.values.map(\.nextDueElapsedNS).min() else {
                break
            }
            if wakeElapsedNS <= now {
                continue
            }
            do {
                try await clock.sleep(untilElapsedNS: wakeElapsedNS)
            } catch {
                break
            }
        }
    }

    private func dueScheduleKind(at elapsedNS: Int64) -> SamplingScheduleKind? {
        schedules
            .filter { $0.value.nextDueElapsedNS <= elapsedNS }
            .map(\.key)
            .sorted()
            .first
    }

    private func executeRead(for kind: SamplingScheduleKind, plannedDueElapsedNS: Int64) async {
        guard running, let schedule = schedules[kind], !readInFlight else { return }
        let requestedPeriodMS = schedule.periodMS
        let generation = catalogGeneration ?? 0
        // Capture terminal callbacks before any await; stop must not erase cleanup.
        let startHandler = willRead
        let finishHandler = didFinishRead
        let handler = onRead
        readInFlight = true
        defer { readInFlight = false }
        let requestID = makeRequestID()
        let lease: PersistenceLease
        do {
            try Task.checkCancellation()
            lease = try await reservation.reserve(owner: .request(requestID), generation: generation,
                maxRecords: configuration.writerReserveRecordsPerEvent, maxBytes: configuration.writerMaxPayloadBytes)
        } catch {
            advanceScheduleAfterRead(kind: kind, schedule: schedule, generation: generation, plannedDue: plannedDueElapsedNS)
            return
        }

        var registered = false
        do {
            try Task.checkCancellation()
            if let startHandler {
                await startHandler(requestID, plannedDueElapsedNS)
                registered = true
            }
            try Task.checkCancellation()
            let batch = try await client.read(ReadRequest(requestID: requestID, sourceIDs: schedule.sourceIDs, requestedPeriodMS: requestedPeriodMS))
            try Task.checkCancellation()
            if running, batch.generation == generation, let handler {
                await handler(SamplingReadEvent(kind: kind, plannedElapsedNS: plannedDueElapsedNS,
                    requestID: requestID, requestedPeriodMS: requestedPeriodMS, lease: lease, batch: batch))
                stats.completedReads += 1
            } else {
                await reservation.cancel(lease)
            }
        } catch {
            await reservation.cancel(lease)
        }
        if registered, let finishHandler { await finishHandler(requestID, plannedDueElapsedNS) }
        advanceScheduleAfterRead(kind: kind, schedule: schedule, generation: generation, plannedDue: plannedDueElapsedNS)
    }

    private func advanceScheduleAfterRead(kind: SamplingScheduleKind, schedule: ScheduleState, generation: UInt64, plannedDue: Int64) {
        guard running, catalogGeneration == generation else { return }
        let now = clock.now().elapsedNS
        skipOverdueSchedules(except: kind, nowElapsedNS: now)
        // A picker change during IO has already scheduled the next read.
        guard schedules[kind] == schedule else { return }
        let (nextDue, skipped) = SchedulePlanner.advanceAfterPlannedRead(
            plannedDueElapsedNS: plannedDue, periodMS: schedule.periodMS, nowElapsedNS: now)
        var next = schedule
        next.nextDueElapsedNS = nextDue
        schedules[kind] = next
        recordSkipped(kind: kind, count: skipped)
    }

    private func skipOverdueSchedules(except activeKind: SamplingScheduleKind, nowElapsedNS: Int64) {
        for kind in SamplingScheduleKind.allCases where kind != activeKind {
            guard var schedule = schedules[kind] else {
                continue
            }
            let (nextDue, skipped) = SchedulePlanner.skipOverdue(
                nextDueElapsedNS: schedule.nextDueElapsedNS,
                periodMS: schedule.periodMS,
                nowElapsedNS: nowElapsedNS
            )
            schedule.nextDueElapsedNS = nextDue
            schedules[kind] = schedule
            recordSkipped(kind: kind, count: skipped)
        }
    }

    private func recordSkipped(kind: SamplingScheduleKind, count: Int) {
        guard count > 0 else {
            return
        }
        stats.skippedByKind[kind, default: 0] += count
    }

    private func makeRequestID() -> RequestID { RequestID(UUID()) }

    private static func makeSchedules(
        catalog: QualifiedSourceCatalog,
        cpuPeriodMS: Int,
        ssdIntervalMS: Int,
        batteryIntervalMS: Int,
        startElapsedNS: Int64
    ) -> [SamplingScheduleKind: ScheduleState] {
        var schedules: [SamplingScheduleKind: ScheduleState] = [:]
        let cpuSources = catalog.available.filter { $0.kind == .cpuZone }.map(\.sourceID)
        if !cpuSources.isEmpty {
            schedules[.cpu] = ScheduleState(
                kind: .cpu,
                periodMS: cpuPeriodMS,
                nextDueElapsedNS: startElapsedNS + Int64(cpuPeriodMS) * 1_000_000,
                sourceIDs: cpuSources
            )
        }
        let ssdSources = catalog.available.filter { $0.kind == .ssd }.map(\.sourceID)
        if !ssdSources.isEmpty {
            schedules[.ssd] = ScheduleState(
                kind: .ssd,
                periodMS: ssdIntervalMS,
                nextDueElapsedNS: startElapsedNS + Int64(ssdIntervalMS) * 1_000_000,
                sourceIDs: ssdSources
            )
        }
        let batterySources = catalog.available.filter { $0.kind == .battery }.map(\.sourceID)
        if !batterySources.isEmpty {
            schedules[.battery] = ScheduleState(
                kind: .battery,
                periodMS: batteryIntervalMS,
                nextDueElapsedNS: startElapsedNS + Int64(batteryIntervalMS) * 1_000_000,
                sourceIDs: batterySources
            )
        }
        return schedules
    }
}
