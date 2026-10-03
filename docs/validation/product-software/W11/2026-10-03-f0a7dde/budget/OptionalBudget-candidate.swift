import Foundation
import Testing
@testable import SensorRuntime
@testable import TemperatureCore

@Suite(.serialized) struct OptionalProbeBudgetAcrossReconnectTests {
    @Test(arguments: [2, 125])
    func unrelatedCPUReconnectMustNotRestartExhaustedOptionalProbeBudget(pollDelayMS: Int) async throws {
        let profile = try Configuration.bundledProfile()
        let configuration = try Configuration.bundledDefaults()
        let clock = OptionalPhaseClock(now: Fixtures.timestamp(ms: 0))
        let sources = profile.cpuKeys.map { DiscoveredSource(transportHandle: "smc:\($0)", provider: .smc, rawKey: $0,
            registryID: "review-\($0)", encoding: profile.expectedSMCEncoding, byteCount: profile.expectedSMCSizeBytes) }
            + [DiscoveredSource(transportHandle: "nvme:12345", provider: .nvme, rawKey: "TEMPERATURE", registryID: "12345",
                encoding: "uint16_le_kelvin", byteCount: 2, physicalInterconnectLocation: "Internal", interconnectLookupStatus: .found)]
        let registry = ProfileRegistry(profile: profile)
        let oldCatalog = try registry.qualify(DiscoveredCatalog(generation: 1, sources: sources))
        let newCatalog = try registry.qualify(DiscoveredCatalog(generation: 2, sources: sources))
        let oldSSD = try #require(SeriesCatalogBuilder.definitions(from: oldCatalog).first { $0.kind == .ssd })
        let newSSD = try #require(SeriesCatalogBuilder.definitions(from: newCatalog).first { $0.kind == .ssd })
        let newCPU = try #require(SeriesCatalogBuilder.definitions(from: newCatalog).first { $0.kind == .cpuMain })
        let receipts = BudgetReceiptLog()
        let transport = BudgetProbeTransport(clock: clock, sources: sources)
        let client = QualifiedSensorClient(transport: transport, registry: registry)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OptionalProbeBudget-\(UUID())")
        let databaseURL = root.appendingPathComponent("monitor.sqlite")
        let session = SessionPersistenceActor(databaseURL: databaseURL, configuration: configuration,
            batchCommitOperation: { store, batch, sessionID, generation in
                let receipt = try store.commitBatch(batch, sessionID: sessionID, snapshotGeneration: generation)
                receipts.recordCommitted()
                return receipt
            })
        let controller = SessionMonitorController(clock: clock, client: client, session: session,
            sessionMetadata: SessionMetadata(sessionID: SessionID(UUID()), startedWallUnixNS: 1, model: "Mac16,13", osBuild: "24G419", appVersion: "review"), configuration: configuration)
        let snapshots = BudgetSnapshotLog()
        let stream = await controller.snapshots()
        let observer = Task { for await snapshot in stream { await snapshots.append(snapshot) } }
        let driver = BudgetPhaseDriver(clock: clock, snapshots: snapshots, pollDelayMS: pollDelayMS)
        do {
            try await controller.start()
            clock.advance(to: Fixtures.timestamp(ms: 500))
            try await driver.wait("identify-sampling-retry550") { clock.identifySamplingTask(waitingUntilMS: 550) }
            try await driver.wait("identify-snapshot700") {
                await snapshots.latestElapsedNS >= 500_000_000 && clock.identifySnapshotTask(waitingUntilMS: 700)
            }
            for retryMS in [Int64(550), 650, 850] {
                try await driver.wait("initial-retry-\(retryMS)") { clock.hasSamplingSleep(untilMS: retryMS) }
                clock.advance(to: Fixtures.timestamp(ms: retryMS))
            }
            // The same sampling task sleeps only after failure Receipt,
            // quarantine and the following CPU read have all returned.
            try await driver.wait("initial-quarantine-receipt") { clock.hasSamplingSleep(untilMS: 1000) }
            #expect(await transport.optionalReads == 4)
            try await driver.publishSnapshot("initial-unavailable", beforeMS: 60_850)
            #expect(await snapshots.hasUnavailableSSD)
            let reader = try SQLiteStore(databaseURL: databaseURL)
            defer { reader.close() }
            func committedCount(_ seriesID: SeriesID) throws -> Int64 {
                try #require(try reader.queryInt64("SELECT COUNT(*) FROM raw_samples WHERE series_id = '\(seriesID.rawValue)'"))
            }
            #expect(try committedCount(oldSSD.seriesID) == 0)
            #expect(try reader.queryInt64("SELECT COUNT(*) FROM gaps WHERE series_id = '\(oldSSD.seriesID.rawValue)'") == 1)
            // Every failed recovery probe schedules its next round 60s after
            // completion. Poll latency must not govern virtual time progression.
            for (readMS, expected) in [(Int64(60_850), 5), (120_850, 6), (180_850, 7)] {
                let before = receipts.committedBatches
                clock.advance(to: Fixtures.timestamp(ms: readMS))
                try await driver.wait("failed-recovery-receipt-\(expected - 4)") {
                    await transport.optionalReads == expected && receipts.committedBatches > before
                        && clock.nextSamplingDeadlineNS != nil
                }
                #expect(try committedCount(oldSSD.seriesID) == 0, "Failure facts must not become temperature samples")
                #expect(await controller.lastAcceptFailure()?.severity != .fatal)
                print("BUDGET_PHASE_PROBE pollMS=\(pollDelayMS) round=\(expected - 4) elapsed=\(clock.now().elapsedNS) reads=\(await transport.optionalReads) commits=\(receipts.committedBatches) nextSampling=\(clock.nextSamplingDeadlineNS ?? -1)")
            }
            #expect(await transport.optionalReads == 7)
            await transport.armCPUTimeout()
            let cpuDueNS = try #require(clock.nextSamplingDeadlineNS)
            let cpuDueMS = cpuDueNS / 1_000_000
            clock.advance(to: Fixtures.timestamp(ms: cpuDueMS))
            let retryMS = cpuDueMS + 50
            try await driver.wait("cpu-timeout-retry") { clock.hasSamplingSleep(untilMS: retryMS) }
            clock.advance(to: Fixtures.timestamp(ms: retryMS))
            try await driver.wait("generation2-catalog-and-cpu-receipt") {
                await transport.discoverCount == 2 && clock.nextSamplingDeadlineNS != nil
            }
            #expect(try committedCount(newCPU.seriesID) > 0, "Required CPU sampling must recover and commit after reconnect")
            // Cross both the new catalog's ordinary SSD due time and a full
            // optional recovery interval. Each advance waits for the identified
            // sampling task's next sleep, including failure/callback completion.
            for targetMS in [retryMS + 1000, retryMS + 61_000] {
                clock.advance(to: Fixtures.timestamp(ms: targetMS))
                try await driver.wait("exhausted-budget-boundary-\(targetMS)") { clock.nextSamplingDeadlineNS != nil }
                #expect(await transport.optionalReads == 7)
                #expect(await transport.newOptionalReads == 0, "Three failed per-session recovery rounds must remain exhausted across CPU reconnect; only wake/restart permits another qualification cycle")
                #expect(try committedCount(newSSD.seriesID) == 0)
                #expect(try committedCount(newCPU.seriesID) > 0)
            }
            try await driver.publishSnapshot("generation2-published", beforeMS: retryMS + 62_000)
            #expect(await snapshots.hasGeneration2SSD)
            #expect(await snapshots.newSSDIsUnavailable, "Stopped optional sampling must remain unavailable in the published generation")
            #expect(await transport.optionalReads == 7)
            #expect(await transport.newOptionalReads == 0)
            #expect(await controller.lastAcceptFailure()?.severity != .fatal)
            print("BUDGET_PHASE_COMPLETE pollMS=\(pollDelayMS) optional=\(await transport.optionalReads) newOptional=\(await transport.newOptionalReads) commits=\(receipts.committedBatches) elapsed=\(clock.now().elapsedNS)")
            reader.close()
            await controller.stop()
            await observer.value
        } catch {
            print("BUDGET_PHASE_FAILURE pollMS=\(pollDelayMS) elapsed=\(clock.now().elapsedNS) optional=\(await transport.optionalReads) newOptional=\(await transport.newOptionalReads) discoveries=\(await transport.discoverCount) commits=\(receipts.committedBatches) snapshot=\(await snapshots.latestElapsedNS) sleeps=\(clock.sleepDescription) error=\(error)")
            await controller.stop()
            observer.cancel()
            await observer.value
            throw error
        }
    }
}

private actor BudgetProbeTransport: SensorTransport {
    let clock: OptionalPhaseClock
    let sources: [DiscoveredSource]
    private(set) var discoverCount = 0
    private(set) var optionalReads = 0
    private(set) var newOptionalReads = 0
    private var shouldFailCPU = false
    init(clock: OptionalPhaseClock, sources: [DiscoveredSource]) { self.clock = clock; self.sources = sources }
    func armCPUTimeout() { shouldFailCPU = true }
    func discoverRaw() async throws -> DiscoveredCatalog {
        discoverCount += 1
        return DiscoveredCatalog(generation: UInt64(discoverCount), sources: sources)
    }
    func readRaw(_ request: TransportReadRequest) async throws -> TransportReadBatch {
        if request.transportHandles.contains(where: { $0.hasPrefix("smc:") }) {
            if shouldFailCPU {
                shouldFailCPU = false
                throw MonitorFailure(code: .sensorTimeout, severity: .degraded, component: "GenerationProbe", operation: "read", retryCount: 0, sourceID: nil, underlyingCode: "cpu_timeout_between_optional_probes")
            }
        } else {
            optionalReads += 1
            if request.generation == 2 { newOptionalReads += 1 }
            if true {
                throw MonitorFailure(code: .sensorRead, severity: .degraded, component: "GenerationProbe", operation: "read", retryCount: 0, sourceID: nil, underlyingCode: "initial_optional_failure")
            }
        }
        let now = clock.now()
        return TransportReadBatch(requestID: request.requestID, generation: request.generation,
            readings: request.transportHandles.map { TransportReading(transportHandle: $0, started: now, finished: now,
                outcome: .success(valueC: 70, sourceWallUnixNS: nil, freshness: .unknown)) })
    }
    func close() async {}
}

private actor BudgetSnapshotLog {
    private var latest: Snapshot?
    func append(_ snapshot: Snapshot) { latest = snapshot }
    var latestElapsedNS: Int64 { latest?.asOf.elapsedNS ?? -1 }
    var hasGeneration2SSD: Bool { latest?.values.contains { $0.definition.kind == .ssd && $0.definition.definitionVersion == 2 } ?? false }
    var hasUnavailableSSD: Bool {
        guard let state = latest?.values.first(where: { $0.definition.kind == .ssd })?.state else { return false }
        if case .unavailable(capability: .failed, reason: _) = state { return true }; return false
    }
    var newSSDIsAvailable: Bool {
        guard let value = latest?.values.first(where: { $0.definition.kind == .ssd && $0.definition.definitionVersion == 2 }) else { return false }
        if case .available = value.state { return true }; return false
    }
    var newSSDIsUnavailable: Bool {
        guard let value = latest?.values.first(where: { $0.definition.kind == .ssd && $0.definition.definitionVersion == 2 }) else { return false }
        if case .unavailable(capability: .failed, reason: _) = value.state { return true }; return false
    }
}

private final class BudgetReceiptLog: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var committedBatches: Int { lock.withLock { count } }
    func recordCommitted() { lock.withLock { count += 1 } }
}

private struct BudgetPhaseDriver {
    let clock: OptionalPhaseClock
    let snapshots: BudgetSnapshotLog
    let pollDelayMS: Int
    func wait(_ phase: String, timeout: Duration = .seconds(4), _ predicate: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !(await predicate()) {
            guard ContinuousClock.now < deadline else {
                throw BudgetPhaseTimeout(phase: phase, elapsedNS: clock.now().elapsedNS, sleeps: clock.sleepDescription)
            }
            // Poll latency can vary without changing virtual-time progression.
            try await Task.sleep(for: .milliseconds(pollDelayMS))
        }
    }
    func publishSnapshot(_ phase: String, beforeMS: Int64) async throws {
        try await wait(phase + "-publisher-registration") { clock.nextSnapshotDeadlineNS != nil }
        let target = try #require(clock.nextSnapshotDeadlineNS)
        try #require(target < beforeMS * 1_000_000, "Publishing must not start another optional probe")
        clock.advance(to: Fixtures.timestamp(ms: target / 1_000_000))
        try await wait(phase + "-snapshot", timeout: .seconds(2)) { await snapshots.latestElapsedNS >= target }
        try await wait(phase + "-sampling-callback") { clock.nextSamplingDeadlineNS != nil }
    }
}

private struct BudgetPhaseTimeout: Error, CustomStringConvertible {
    let phase: String
    let elapsedNS: Int64
    let sleeps: String
    var description: String { "Budget phase timed out: \(phase), elapsed=\(elapsedNS), sleeps=\(sleeps)" }
}
