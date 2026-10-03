import Foundation
import Testing
@testable import SensorRuntime
@testable import TemperatureCore

@Suite(.serialized) struct OptionalGenerationRecoveryRegressionTests {
    @Test(arguments: [2, 125])
    func sourceGenerationChangeRequiresThreeNewOptionalReceipts(pollDelayMS: Int) async throws {
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
        let receipts = GenerationReceiptLog(oldSeriesID: oldSSD.seriesID, newSeriesID: newSSD.seriesID)
        let transport = GenerationProbeTransport(clock: clock, sources: sources)
        let client = QualifiedSensorClient(transport: transport, registry: registry)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OptionalGeneration-\(UUID())")
        let databaseURL = root.appendingPathComponent("monitor.sqlite")
        let session = SessionPersistenceActor(databaseURL: databaseURL, configuration: configuration,
            batchCommitOperation: { store, batch, sessionID, generation in
                let receipt = try store.commitBatch(batch, sessionID: sessionID, snapshotGeneration: generation)
                receipts.recordCommitted(batch)
                return receipt
            })
        let controller = SessionMonitorController(clock: clock, client: client, session: session,
            sessionMetadata: SessionMetadata(sessionID: SessionID(UUID()), startedWallUnixNS: 1, model: "Mac16,13", osBuild: "24G419", appVersion: "review"), configuration: configuration)
        let snapshots = GenerationSnapshotLog()
        let stream = await controller.snapshots()
        let observer = Task { for await snapshot in stream { await snapshots.append(snapshot) } }
        let driver = GenerationPhaseDriver(clock: clock, snapshots: snapshots, pollDelayMS: pollDelayMS)
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
            // This sampling sleep occurs after failure Receipt/quarantine and
            // the following CPU read. Counts alone do not prove callback return.
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
            // The fourth failure completed at850ms. The first recovery probe is
            // due60s later; subsequent probes use the configured500ms cadence.
            for (readMS, expected) in [(Int64(60_850), 1), (61_350, 2)] {
                clock.advance(to: Fixtures.timestamp(ms: readMS))
                try await driver.wait("old-receipt-\(expected)") {
                    receipts.oldCommitted == expected && clock.nextSamplingDeadlineNS != nil
                }
                #expect(await transport.optionalReads == expected + 4)
                #expect(try committedCount(oldSSD.seriesID) == Int64(expected))
                try await driver.publishSnapshot("old-unavailable-\(expected)", beforeMS: readMS + 500)
                #expect(await snapshots.hasUnavailableSSD)
            }
            #expect(receipts.oldCommitted == 2)
            #expect(await transport.optionalReads == 6)
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
            #expect(receipts.oldCommitted == 2, "Reconnect must precede the third old-source success")
            #expect(await transport.newOptionalReads == 0)
            #expect(try committedCount(oldSSD.seriesID) == 2)
            // SSD retained its scheduled61850ms deadline across CPU reconnect.
            for (readMS, expected) in [(Int64(61_850), 1), (62_350, 2), (62_850, 3)] {
                clock.advance(to: Fixtures.timestamp(ms: readMS))
                try await driver.wait("new-receipt-\(expected)") {
                    receipts.newCommitted == expected && clock.nextSamplingDeadlineNS != nil
                }
                #expect(await transport.newOptionalReads == expected)
                #expect(try committedCount(newSSD.seriesID) == Int64(expected))
                try await driver.publishSnapshot("new-published-\(expected)", beforeMS: readMS + 500)
                #expect(await snapshots.hasGeneration2SSD)
                if expected < 3 {
                    #expect(await snapshots.newSSDIsUnavailable, "Generation2 requires three new committed reads")
                } else {
                    #expect(await snapshots.newSSDIsAvailable)
                }
                #expect(await controller.lastAcceptFailure() == nil)
            }
            #expect(receipts.oldCommitted == 2)
            #expect(receipts.newCommitted == 3)
            print("GEN_PHASE_COMPLETE pollMS=\(pollDelayMS) oldReceipts=\(receipts.oldCommitted) newReceipts=\(receipts.newCommitted) elapsed=\(clock.now().elapsedNS)")
            reader.close()
            await controller.stop()
            await observer.value
        } catch {
            print("GEN_PHASE_FAILURE pollMS=\(pollDelayMS) elapsed=\(clock.now().elapsedNS) optional=\(await transport.optionalReads) newOptional=\(await transport.newOptionalReads) discoveries=\(await transport.discoverCount) oldReceipts=\(receipts.oldCommitted) newReceipts=\(receipts.newCommitted) snapshot=\(await snapshots.latestElapsedNS) sleeps=\(clock.sleepDescription) error=\(error)")
            await controller.stop()
            observer.cancel()
            await observer.value
            throw error
        }
    }
}

private actor GenerationProbeTransport: SensorTransport {
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
            if optionalReads <= 4 {
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

private actor GenerationSnapshotLog {
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

private final class GenerationReceiptLog: @unchecked Sendable {
    private let lock = NSLock()
    private let oldSeriesID: SeriesID
    private let newSeriesID: SeriesID
    private var oldCount = 0
    private var newCount = 0
    init(oldSeriesID: SeriesID, newSeriesID: SeriesID) { self.oldSeriesID = oldSeriesID; self.newSeriesID = newSeriesID }
    var oldCommitted: Int { lock.withLock { oldCount } }
    var newCommitted: Int { lock.withLock { newCount } }
    func recordCommitted(_ batch: PersistenceBatch) {
        lock.withLock {
            if batch.raw.contains(where: { $0.seriesID == oldSeriesID }) { oldCount += 1 }
            if batch.raw.contains(where: { $0.seriesID == newSeriesID }) { newCount += 1 }
        }
    }
}

private struct GenerationPhaseDriver {
    let clock: OptionalPhaseClock
    let snapshots: GenerationSnapshotLog
    let pollDelayMS: Int
    func wait(_ phase: String, timeout: Duration = .seconds(4), _ predicate: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !(await predicate()) {
            guard ContinuousClock.now < deadline else {
                throw GenerationPhaseTimeout(phase: phase, elapsedNS: clock.now().elapsedNS, sleeps: clock.sleepDescription)
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

private struct GenerationPhaseTimeout: Error, CustomStringConvertible {
    let phase: String
    let elapsedNS: Int64
    let sleeps: String
    var description: String { "Generation phase timed out: \(phase), elapsed=\(elapsedNS), sleeps=\(sleeps)" }
}
