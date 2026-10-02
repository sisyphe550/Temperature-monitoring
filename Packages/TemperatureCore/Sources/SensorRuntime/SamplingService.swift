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
    public typealias FailureHandler = @Sendable (MonitorFailure, SamplingScheduleKind) async -> Void
    public typealias RecoveryHandler = @Sendable (QualifiedSourceCatalog) async throws -> Void
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
    private var onFailure: FailureHandler?
    private var onRecoveredCatalog: RecoveryHandler?
    private let errors: ErrorCoordinator
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
        errors = ErrorCoordinator(policy: RetryPolicy(configuration: configuration))
        cpuPeriodMS = configuration.cpuDefaultMS
    }

    public func start(
        catalog: QualifiedSourceCatalog,
        willRead: WillReadHandler? = nil,
        didFinishRead: WillReadHandler? = nil,
        onFailure: FailureHandler? = nil,
        onRecoveredCatalog: RecoveryHandler? = nil,
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
        self.onFailure = onFailure
        self.onRecoveredCatalog = onRecoveredCatalog
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
        onFailure = nil
        onRecoveredCatalog = nil
        catalogGeneration = nil
        schedules = [:]
    }

    // A callback running on the sampling task cannot await that task's value.
    public func requestStop() { running = false; loopTask?.cancel() }

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
        guard running, var schedule = schedules[kind], !readInFlight else { return }
        readInFlight = true
        defer { readInFlight = false }
        await errors.reset(domain: .sensor)
        var generation = catalogGeneration ?? 0
        var failureIndex = 0
        while running, !Task.isCancelled {
            do {
                try await performRead(kind: kind, schedule: schedule, generation: generation, plannedDue: plannedDueElapsedNS)
                await errors.reset(domain: .sensor)
                break
            } catch is CancellationError {
                if !Task.isCancelled { advanceScheduleAfterRead(kind: kind, schedule: schedule, generation: generation, plannedDue: plannedDueElapsedNS) }
                return
            }
            catch {
                let failure = Self.monitorFailure(error, retryCount: failureIndex)
                let resolution = await errors.evaluate(failure: failure, context: ErrorEvaluationContext(domain: .sensor,
                    sourceKind: kind == .cpu ? .cpuZone : (kind == .ssd ? .ssd : .battery), isRequiredSource: kind == .cpu))
                switch resolution {
                case let .retry(waitMS, _):
                    await onFailure?(failure, kind)
                    failureIndex += 1
                    do {
                        try await clock.sleep(untilElapsedNS: clock.now().elapsedNS + Int64(waitMS) * 1_000_000)
                        try Task.checkCancellation()
                        if failure.code == .sensorTimeout || error is QualifiedSensorClientError {
                            let recovered = try await client.discover()
                            _ = try SeriesCatalogBuilder.definitions(from: recovered)
                            try await onRecoveredCatalog?(recovered)
                            guard running else { return }
                            generation = recovered.generation
                            catalogGeneration = recovered.generation
                            schedule.sourceIDs = recovered.available.filter {
                                $0.kind == (kind == .cpu ? .cpuZone : (kind == .ssd ? .ssd : .battery))
                            }.map(\.sourceID)
                            guard !schedule.sourceIDs.isEmpty else { throw Self.monitorFailure(QualifiedSensorClientError.unknownSourceID, retryCount: failureIndex) }
                            if var current = schedules[kind] { current.sourceIDs = schedule.sourceIDs; schedules[kind] = current; schedule = current }
                        }
                    } catch is CancellationError { return }
                    catch {
                        let fatal = Self.withSeverity(Self.monitorFailure(error, retryCount: failureIndex), .fatal)
                        await onFailure?(fatal, kind)
                        requestStop()
                        return
                    }
                case .fatal:
                    let final = MonitorFailure(code: RetryPolicy(configuration: configuration).isRetryable(failure, domain: .sensor) ? .sensorRead : failure.code,
                        severity: .fatal, component: failure.component, operation: failure.operation,
                        retryCount: failureIndex, sourceID: failure.sourceID, underlyingCode: failure.underlyingCode)
                    await onFailure?(final, kind)
                    requestStop()
                    return
                case let .markUnavailable(unavailable):
                    await onFailure?(unavailable, kind)
                    schedules.removeValue(forKey: kind)
                    return
                }
            }
        }
        advanceScheduleAfterRead(kind: kind, schedule: schedule, generation: generation, plannedDue: plannedDueElapsedNS)
    }

    private func performRead(kind: SamplingScheduleKind, schedule: ScheduleState, generation: UInt64, plannedDue: Int64) async throws {
        let requestID = makeRequestID()
        let lease = try await reserveWhenWritable(requestID: requestID, generation: generation)
        let startHandler = willRead
        let finishHandler = didFinishRead
        let handler = onRead
        let started = clock.now()
        var registered = false
        var readFailure: MonitorFailure?
        do {
            try Task.checkCancellation()
            if let startHandler { await startHandler(requestID, plannedDue); registered = true }
            try Task.checkCancellation()
            let batch: ReadBatch
            do {
                batch = try await client.read(ReadRequest(requestID: requestID, sourceIDs: schedule.sourceIDs, requestedPeriodMS: schedule.periodMS))
            } catch is CancellationError { throw CancellationError() }
            catch {
                let failure = Self.monitorFailure(error, retryCount: 0)
                // Persist only failure facts, never a replacement temperature.
                if failure.code == .sensorTimeout || failure.code == .sensorRead || failure.code == .sensorValue {
                    let finished = clock.now()
                    let failed = ReadBatch(requestID: requestID, generation: generation, requestedPeriodMS: schedule.periodMS,
                        readings: schedule.sourceIDs.map { Reading(sourceID: $0, started: started, finished: finished, outcome: .failure(failure)) })
                    if let handler { await handler(SamplingReadEvent(kind: kind, plannedElapsedNS: plannedDue, requestID: requestID, requestedPeriodMS: schedule.periodMS, lease: lease, batch: failed)) }
                    else { await reservation.cancel(lease) }
                } else { await reservation.cancel(lease) }
                throw failure
            }
            try Task.checkCancellation()
            guard batch.generation == generation else { throw CancellationError() }
            guard Set(batch.readings.map(\.sourceID)) == Set(schedule.sourceIDs), batch.readings.count == schedule.sourceIDs.count else {
                throw MonitorFailure(code: .sensorProtocol, severity: .fatal, component: "SamplingService", operation: "read", retryCount: 0, sourceID: nil, underlyingCode: "reading_members_mismatch")
            }
            let normalized = batch.readings.map { reading -> Reading in
                if case let .success(value, _, _) = reading.outcome, !value.isFinite || value < -273.15 {
                    return Reading(sourceID: reading.sourceID, started: reading.started, finished: reading.finished,
                        outcome: .failure(MonitorFailure(code: .sensorValue, severity: .degraded, component: "SamplingService", operation: "read", retryCount: 0, sourceID: reading.sourceID, underlyingCode: "invalid_temperature")))
                }
                return reading
            }
            readFailure = normalized.compactMap { reading -> MonitorFailure? in if case let .failure(failure) = reading.outcome { return failure }; return nil }.first
            if kind == .cpu, readFailure == nil,
               let first = normalized.map(\.finished.elapsedNS).min(), let last = normalized.map(\.finished.elapsedNS).max(),
               last - first > Int64(configuration.cpuMaxBatchSpanMS) * 1_000_000 {
                readFailure = MonitorFailure(code: .sensorRead, severity: .degraded, component: "SamplingService", operation: "cpuMaximum", retryCount: 0, sourceID: nil, underlyingCode: "cpu_batch_span_exceeded")
            }
            if running, let handler {
                await handler(SamplingReadEvent(kind: kind, plannedElapsedNS: plannedDue, requestID: requestID, requestedPeriodMS: schedule.periodMS, lease: lease,
                    batch: ReadBatch(requestID: batch.requestID, generation: batch.generation, requestedPeriodMS: batch.requestedPeriodMS, readings: normalized)))
                stats.completedReads += 1
            } else { await reservation.cancel(lease) }
        } catch {
            await reservation.cancel(lease)
            if registered { await finishHandler?(requestID, plannedDue) }
            throw error
        }
        if registered { await finishHandler?(requestID, plannedDue) }
        if let readFailure { throw readFailure }
    }

    private static func monitorFailure(_ error: Error, retryCount: Int) -> MonitorFailure {
        if let failure = error as? MonitorFailure {
            return MonitorFailure(code: failure.code, severity: failure.severity, component: failure.component,
                operation: failure.operation, retryCount: retryCount, sourceID: failure.sourceID, underlyingCode: failure.underlyingCode)
        }
        let qualified = error as? QualifiedSensorClientError
        let code: MonitorErrorCode = (qualified == .generationMismatch || qualified == .notDiscovered) ? .sensorTimeout
            : (qualified == nil ? .sensorRead : .sensorProtocol)
        return MonitorFailure(code: code,
            severity: .degraded, component: "SamplingService", operation: "read", retryCount: retryCount,
            sourceID: nil, underlyingCode: String(describing: error))
    }

    private static func withSeverity(_ failure: MonitorFailure, _ severity: Severity) -> MonitorFailure {
        MonitorFailure(code: failure.code, severity: severity, component: failure.component,
            operation: failure.operation, retryCount: failure.retryCount, sourceID: failure.sourceID, underlyingCode: failure.underlyingCode)
    }

    private func reserveWhenWritable(requestID: RequestID, generation: UInt64) async throws -> PersistenceLease {
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(configuration.writerMaxOldestAgeMS))
        while true {
            try Task.checkCancellation()
            do {
                return try await reservation.reserve(owner: .request(requestID), generation: generation,
                    maxRecords: configuration.writerReserveRecordsPerEvent, maxBytes: configuration.writerMaxPayloadBytes)
            } catch let failure as MonitorFailure where failure.code == .databaseBackpressure {
                guard ContinuousClock.now < deadline else { throw failure }
                // Backpressure pauses IO. A brief watermark write must not discard
                // the only due CPU opportunity before the writer becomes free.
                try await ContinuousClock().sleep(for: .milliseconds(configuration.writerFlushMS))
            }
        }
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
