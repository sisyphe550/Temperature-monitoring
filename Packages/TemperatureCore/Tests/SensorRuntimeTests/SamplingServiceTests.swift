import Foundation
import Testing
@testable import SensorRuntime
import TemperatureCore

@Suite(.serialized) struct SamplingServiceTests {
    @Test func fiftyMillisecondPeriodWithOneTwentyMillisecondReadDoesNotOverlap() async throws {
        let clock = SchedulingTestClock(now: timestamp(ms: 0))
        let catalog = try makeCatalog(kinds: [.cpuZone])
        let client = MockScheduleSensorClient(clock: clock, catalog: catalog, readDurationMS: 120)
        let configuration = try Configuration.bundledDefaults()
        let service = SamplingService(clock: clock, client: client, configuration: configuration)

        await service.start(catalog: catalog) { _ in }
        await service.setCPUPeriod(milliseconds: 50)
        clock.advance(to: timestamp(ms: 50))
        try await waitUntil { await client.readCount >= 1 }
        clock.advance(to: timestamp(ms: 200))
        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(await client.readCount == 1)
        #expect(await client.maxConcurrentReads == 1)
        #expect(await service.statistics().skippedByKind[.cpu, default: 0] >= 1)
        await service.stop()
    }

    @Test func simultaneousDueSchedulesPreferCPU() async throws {
        let clock = SchedulingTestClock(now: timestamp(ms: 0))
        let catalog = try makeCatalog(kinds: [.cpuZone, .ssd])
        let client = MockScheduleSensorClient(clock: clock, catalog: catalog)
        let configuration = try makeScheduleConfiguration(cpuMS: 1000, ssdMS: 1000)
        let service = SamplingService(clock: clock, client: client, configuration: configuration)

        let events = EventCollector()
        await service.start(catalog: catalog) { event in
            await events.append(event.kind)
        }
        clock.advance(to: timestamp(ms: 1000))
        try await waitUntil { await client.readCount >= 2 }

        #expect(await events.prefix(2) == [.cpu, .ssd])
        await service.stop()
    }

    @Test func cpuPeriodChangeRecalculatesNextDue() async throws {
        let clock = SchedulingTestClock(now: timestamp(ms: 0))
        let catalog = try makeCatalog(kinds: [.cpuZone])
        let client = MockScheduleSensorClient(clock: clock, catalog: catalog)
        let configuration = try Configuration.bundledDefaults()
        let service = SamplingService(clock: clock, client: client, configuration: configuration)

        await service.start(catalog: catalog) { _ in }
        clock.advance(to: timestamp(ms: 200))
        try await waitUntil { await client.readCount == 1 }

        clock.advance(to: timestamp(ms: 250))
        await service.setCPUPeriod(milliseconds: 500)
        #expect(await service.nextDueElapsedNS(for: .cpu) == 750 * 1_000_000)

        clock.advance(to: timestamp(ms: 400))
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(await client.readCount == 1)

        clock.advance(to: timestamp(ms: 750))
        try await waitUntil { await client.readCount == 2 }
        await service.stop()
    }

    @Test func inFlightReadKeepsOldPeriodAfterPeriodChange() async throws {
        let clock = SchedulingTestClock(now: timestamp(ms: 0))
        let catalog = try makeCatalog(kinds: [.cpuZone])
        let client = MockScheduleSensorClient(clock: clock, catalog: catalog, readDurationMS: 80)
        let configuration = try Configuration.bundledDefaults()
        let service = SamplingService(clock: clock, client: client, configuration: configuration)

        await service.start(catalog: catalog) { _ in }
        clock.advance(to: timestamp(ms: 200))
        try await waitUntil { await client.readCount == 1 }
        await service.setCPUPeriod(milliseconds: 500)
        #expect(await client.readPeriods.first == 200)
        clock.advance(to: timestamp(ms: 280))
        await service.stop()
    }

    @Test func stopDuringWaitEndsScheduling() async throws {
        let clock = SchedulingTestClock(now: timestamp(ms: 0))
        let catalog = try makeCatalog(kinds: [.cpuZone])
        let client = MockScheduleSensorClient(clock: clock, catalog: catalog)
        let configuration = try Configuration.bundledDefaults()
        let service = SamplingService(clock: clock, client: client, configuration: configuration)

        await service.start(catalog: catalog) { _ in }
        try await Task.sleep(nanoseconds: 20_000_000)
        await service.stop()
        clock.advance(to: timestamp(ms: 500))
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(await client.readCount == 0)
    }

    @Test func optionalSourcesMissingDoNotSchedule() async throws {
        let clock = SchedulingTestClock(now: timestamp(ms: 0))
        let catalog = try makeCatalog(kinds: [.cpuZone])
        let client = MockScheduleSensorClient(clock: clock, catalog: catalog)
        let configuration = try Configuration.bundledDefaults()
        let service = SamplingService(clock: clock, client: client, configuration: configuration)

        await service.start(catalog: catalog) { _ in }
        #expect(await service.nextDueElapsedNS(for: .cpu) != nil)
        #expect(await service.nextDueElapsedNS(for: .ssd) == nil)
        #expect(await service.nextDueElapsedNS(for: .battery) == nil)
        await service.stop()
    }

    @Test func schedulePlannerSkipsOverdueWithoutCatchUp() {
        let (nextDue, skipped) = SchedulePlanner.advanceAfterPlannedRead(
            plannedDueElapsedNS: 50 * 1_000_000,
            periodMS: 50,
            nowElapsedNS: 170 * 1_000_000
        )
        #expect(skipped == 2)
        #expect(nextDue == 200 * 1_000_000)
    }
}

private func timestamp(ms: Int64) -> Timestamp {
    Timestamp(elapsedNS: ms * 1_000_000, wallUnixNS: ms * 1_000_000)
}

private func makeScheduleConfiguration(cpuMS: Int, ssdMS: Int, batteryMS: Int = 1000) throws -> RuntimeConfiguration {
    let defaults = try Configuration.bundledDefaults()
    let data = try JSONEncoder().encode(defaults)
    guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw ConfigurationError.invalidValue("cpu_default_ms")
    }
    object["cpu_default_ms"] = cpuMS
    object["ssd_interval_ms"] = ssdMS
    object["battery_interval_ms"] = batteryMS
    let patched = try JSONSerialization.data(withJSONObject: object)
    return try JSONDecoder().decode(RuntimeConfiguration.self, from: patched)
}

private func makeCatalog(kinds: [SensorKind]) throws -> QualifiedSourceCatalog {
    var available: [QualifiedSource] = []
    for (index, kind) in kinds.enumerated() {
        available.append(
            QualifiedSource(
                sourceID: SourceID(Fixtures.uuid(10 + index)),
                transportHandle: "mock:\(kind.rawValue)-\(index)",
                provider: .smc,
                rawKey: "Tp0\(index)",
                registryID: nil,
                connectionGeneration: 1,
                kind: kind,
                encoding: "flt ",
                unitEvidence: "test",
                evidence: .targetQualified,
                mappingVersion: "test-v1"
            )
        )
    }
    return QualifiedSourceCatalog(generation: 1, available: available, unavailable: [])
}

private func waitUntil(
    timeoutMS: Int64 = 500,
    _ predicate: @escaping () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(Double(timeoutMS) / 1000)
    while Date() < deadline {
        if await predicate() {
            return
        }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
    Issue.record("condition not met before timeout")
}

private actor EventCollector {
    private var kinds: [SamplingScheduleKind] = []

    func append(_ kind: SamplingScheduleKind) {
        kinds.append(kind)
    }

    func prefix(_ count: Int) -> [SamplingScheduleKind] {
        Array(kinds.prefix(count))
    }
}

private enum Fixtures {
    static func uuid(_ ordinal: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", ordinal))!
    }
}

final class SchedulingTestClock: MonitorClock, @unchecked Sendable {
    private struct Waiter {
        let deadline: Int64
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var current: Timestamp
    private var waiters: [UUID: Waiter] = [:]

    init(now: Timestamp) {
        current = now
    }

    func now() -> Timestamp {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func sleep(untilElapsedNS: Int64) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if untilElapsedNS <= current.elapsedNS {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                waiters[id] = Waiter(deadline: untilElapsedNS, continuation: continuation)
                lock.unlock()
            }
        } onCancel: {
            lock.lock()
            if let waiter = waiters.removeValue(forKey: id) {
                lock.unlock()
                waiter.continuation.resume(throwing: CancellationError())
            } else {
                lock.unlock()
            }
        }
    }

    func advance(to timestamp: Timestamp) {
        lock.lock()
        if timestamp.elapsedNS < current.elapsedNS {
            lock.unlock()
            return
        }
        current = timestamp
        let due = waiters.filter { $0.value.deadline <= current.elapsedNS }
        for key in due.keys {
            waiters.removeValue(forKey: key)
        }
        lock.unlock()
        for waiter in due.values {
            waiter.continuation.resume()
        }
    }
}

actor MockScheduleSensorClient: SensorClient {
    let clock: SchedulingTestClock
    let catalog: QualifiedSourceCatalog
    let readDurationMS: Int64
    private(set) var readCount = 0
    private(set) var maxConcurrentReads = 0
    private(set) var readPeriods: [Int] = []
    private var activeReads = 0

    init(clock: SchedulingTestClock, catalog: QualifiedSourceCatalog, readDurationMS: Int64 = 0) {
        self.clock = clock
        self.catalog = catalog
        self.readDurationMS = readDurationMS
    }

    func discover() async throws -> QualifiedSourceCatalog {
        catalog
    }

    func read(_ request: ReadRequest) async throws -> ReadBatch {
        activeReads += 1
        maxConcurrentReads = max(maxConcurrentReads, activeReads)
        readCount += 1
        readPeriods.append(request.requestedPeriodMS)
        if readDurationMS > 0 {
            let target = clock.now().elapsedNS + readDurationMS * 1_000_000
            try await clock.sleep(untilElapsedNS: target)
        }
        activeReads -= 1
        let readings = request.sourceIDs.map { sourceID in
            Reading(
                sourceID: sourceID,
                started: clock.now(),
                finished: clock.now(),
                outcome: .success(valueC: 80, sourceWallUnixNS: nil, freshness: .unknown)
            )
        }
        return ReadBatch(
            requestID: request.requestID,
            generation: catalog.generation,
            readings: readings
        )
    }

    func close() async {}
}
