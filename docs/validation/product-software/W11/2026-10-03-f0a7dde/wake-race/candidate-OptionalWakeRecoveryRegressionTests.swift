import Foundation
import Testing
@testable import SensorRuntime
@testable import TemperatureCore

@Suite(.serialized) struct OptionalWakeRecoveryRegressionTests {
    @Test(arguments: [2, 125])
    func wakeRediscoveryCanRecoverPreviouslyUnavailableOptionalSource(pollDelayMS: Int) async throws {
        let profile = try Configuration.bundledProfile()
        let configuration = try Configuration.bundledDefaults()
        let clock = OptionalPhaseClock(now: Fixtures.timestamp(ms: 0))
        let sources = profile.cpuKeys.map { DiscoveredSource(transportHandle: "smc:\($0)", provider: .smc, rawKey: $0,
            registryID: "review-\($0)", encoding: profile.expectedSMCEncoding, byteCount: profile.expectedSMCSizeBytes) }
            + [DiscoveredSource(transportHandle: "nvme:12345", provider: .nvme, rawKey: "TEMPERATURE", registryID: "12345",
                encoding: "uint16_le_kelvin", byteCount: 2, physicalInterconnectLocation: "Internal", interconnectLookupStatus: .found)]
        let registry = ProfileRegistry(profile: profile)
        let newCatalog = try registry.qualify(DiscoveredCatalog(generation: 2, sources: sources))
        let newDefinitions = try SeriesCatalogBuilder.definitions(from: newCatalog)
        let newSSD = try #require(newDefinitions.first { $0.kind == .ssd })
        let newCPU = try #require(newDefinitions.first { $0.kind == .cpuMain })
        let receipts = WakeReceiptGate(ssdSeriesID: newSSD.seriesID, cpuSeriesID: newCPU.seriesID)

        let transport = WakeProbeTransport(clock: clock, sources: sources)
        let client = QualifiedSensorClient(transport: transport, registry: registry)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OptionalWake-\(UUID())")
        let databaseURL = root.appendingPathComponent("monitor.sqlite")
        let session = SessionPersistenceActor(databaseURL: databaseURL, configuration: configuration,
            batchCommitOperation: { store, batch, sessionID, generation in
                try receipts.beforeCommit(batch)
                let receipt = try store.commitBatch(batch, sessionID: sessionID, snapshotGeneration: generation)
                receipts.recordCommitted(batch)
                return receipt
            })
        let controller = SessionMonitorController(clock: clock, client: client, session: session,
            sessionMetadata: SessionMetadata(sessionID: SessionID(UUID()), startedWallUnixNS: 1, model: "Mac16,13", osBuild: "24G419", appVersion: "review"), configuration: configuration)
        let snapshots = WakeSnapshotLog()
        let stream = await controller.snapshots()
        let observer = Task { for await snapshot in stream { await snapshots.append(snapshot) } }
        let driver = WakePhaseDriver(clock: clock, snapshots: snapshots, pollDelayMS: pollDelayMS)

        do {
            try await controller.start()
            clock.advance(to: Fixtures.timestamp(ms: 500))
            try await driver.wait("identify-initial-sampling") { clock.identifySamplingTask(waitingUntilMS: 550) }
            try await driver.wait("identify-initial-publisher") {
                await snapshots.latestElapsedNS >= 500_000_000 && clock.identifySnapshotTask(waitingUntilMS: 700)
            }
            for retryMS in [Int64(550), 650, 850] {
                try await driver.wait("initial-retry-\(retryMS)") { clock.hasSamplingSleep(untilMS: retryMS) }
                clock.advance(to: Fixtures.timestamp(ms: retryMS))
            }
            try await driver.wait("initial-quarantine-receipt-and-callback") { clock.hasSamplingSleep(untilMS: 1000) }
            #expect(await transport.optionalReads == 4)
            try await driver.publishSnapshot("initial-unavailable", beforeMS: 60_850)
            #expect(await snapshots.hasUnavailableSSD)
            try await controller.suspendForSleep()
            let wakeMS = clock.now().elapsedNS / 1_000_000 + 2_000
            clock.advance(to: Fixtures.timestamp(ms: wakeMS))
            try await controller.resumeAfterWake()
            // Wake starts new sampling/publisher tasks. Their first wake+200
            // sleeps coincide, so identify roles only after the first SSD receipt.
            let firstReadMS = wakeMS + 500
            clock.advance(to: Fixtures.timestamp(ms: firstReadMS))
            try await driver.wait("first-new-SSD-and-CPU-receipts") {
                receipts.committedSSD == 1 && receipts.committedCPU >= 1
            }
            try await driver.wait("reidentify-wake-sampling") {
                clock.identifySamplingTask(waitingUntilMS: firstReadMS + 100)
            }
            try await driver.wait("reidentify-wake-publisher") {
                await snapshots.latestElapsedNS >= firstReadMS * 1_000_000
                    && clock.identifySnapshotTask(waitingUntilMS: firstReadMS + 200)
            }
            let reader = try SQLiteStore(databaseURL: databaseURL)
            defer { reader.close() }
            func count(_ seriesID: SeriesID) throws -> Int64 {
                try #require(try reader.queryInt64("SELECT COUNT(*) FROM raw_samples WHERE series_id = '\(seriesID.rawValue)'"))
            }
            #expect(try count(newCPU.seriesID) >= 1, "Wake CPU must produce a real SQLite commit")
            // Each scheduler sleep proves callback completion after the real
            // store commit and ProcessingReceipt; read counters alone do not.
            for (readMS, expected) in [(firstReadMS, 1), (firstReadMS + 500, 2)] {
                if expected == 2 { clock.advance(to: Fixtures.timestamp(ms: readMS)) }
                try await driver.wait("new-receipt-\(expected)-and-callback") {
                    receipts.committedSSD == expected && clock.nextSamplingDeadlineNS != nil
                }
                #expect(await transport.newOptionalReads == expected)
                #expect(try count(newSSD.seriesID) == Int64(expected))
                try await driver.publishSnapshot("new-unavailable-\(expected)", beforeMS: readMS + 500)
                #expect(await snapshots.hasGeneration2SSD)
                #expect(await snapshots.newSSDIsUnavailable, "One or two new committed readings must not recover the source")
            }
            clock.advance(to: Fixtures.timestamp(ms: firstReadMS + 1_000))
            try await driver.wait("third-new-read-waits-before-commit") { receipts.isBlocked }
            #expect(await transport.newOptionalReads == 3)
            #expect(receipts.committedSSD == 2)
            #expect(try count(newSSD.seriesID) == 2)
            try await driver.publishSnapshot("third-uncommitted", beforeMS: firstReadMS + 1_500, waitForSampling: false)
            #expect(await snapshots.newSSDIsUnavailable, "The third in-flight read is not a committed Receipt")
            receipts.release()
            try await driver.wait("third-receipt-or-fatal") {
                if await controller.lastAcceptFailure()?.severity == .fatal { return true }
                return receipts.committedSSD == 3 && clock.nextSamplingDeadlineNS != nil
            }
            try #require(await controller.lastAcceptFailure() == nil, "A rejected third Receipt must fail this success-path regression")
            #expect(receipts.committedSSD == 3)
            #expect(try count(newSSD.seriesID) == 3)
            try await driver.publishSnapshot("three-new-receipts", beforeMS: firstReadMS + 1_500)
            #expect(await transport.newOptionalReads == 3)
            #expect(await snapshots.hasGeneration2SSD)
            #expect(await snapshots.newSSDIsAvailable, "Three new committed readings must clear the pre-sleep unavailable state")
            print("Wake_PHASE_COMPLETE pollMS=\(pollDelayMS) newReads=\(await transport.newOptionalReads) newReceipts=\(receipts.committedSSD) cpuReceipts=\(receipts.committedCPU)")
            reader.close()
            await controller.stop()
            await observer.value
        } catch {
            print("Wake_PHASE_FAILURE pollMS=\(pollDelayMS) elapsed=\(clock.now().elapsedNS) newReads=\(await transport.newOptionalReads) newReceipts=\(receipts.committedSSD) sleeps=\(clock.sleepDescription) error=\(error)")

            receipts.release()
            await controller.stop()
            observer.cancel()
            await observer.value
            print("Wake_PHASE_CLEANUP_COMPLETE pollMS=\(pollDelayMS)")
            throw error
        }
    }
}

private actor WakeProbeTransport: SensorTransport {
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

private actor WakeSnapshotLog {
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


private final class WakeReceiptGate: @unchecked Sendable {
    private let condition = NSCondition()
    private let ssdSeriesID: SeriesID
    private let cpuSeriesID: SeriesID
    private var ssdCalls = 0
    private var ssdCommitted = 0
    private var cpuCommitted = 0
    private var blocked = false
    private var released = false
    init(ssdSeriesID: SeriesID, cpuSeriesID: SeriesID) { self.ssdSeriesID = ssdSeriesID; self.cpuSeriesID = cpuSeriesID }
    var committedSSD: Int { condition.withLock { ssdCommitted } }
    var committedCPU: Int { condition.withLock { cpuCommitted } }
    var isBlocked: Bool { condition.withLock { blocked } }
    func beforeCommit(_ batch: PersistenceBatch) throws {
        guard batch.raw.contains(where: { $0.seriesID == ssdSeriesID }) else { return }
        condition.lock()
        defer { condition.unlock() }
        ssdCalls += 1
        if ssdCalls == 3 {
            blocked = true
            while !released { condition.wait() }
            blocked = false
            if ProcessInfo.processInfo.environment["OPTIONAL_PHASE_NEGATIVE"] == "reject-third-receipt" {
                throw SQLiteStoreError.integrityConflict(detail: "controlled third optional receipt rejection")
            }
        }
    }
    func recordCommitted(_ batch: PersistenceBatch) {
        condition.withLock {
            ssdCommitted += batch.raw.filter { $0.seriesID == ssdSeriesID }.count
            cpuCommitted += batch.raw.filter { $0.seriesID == cpuSeriesID }.count
        }
    }
    func release() { condition.withLock { released = true; condition.broadcast() } }
}

private struct WakePhaseDriver {
    let clock: OptionalPhaseClock
    let snapshots: WakeSnapshotLog
    let pollDelayMS: Int
    func wait(_ phase: String, timeout: Duration = .seconds(4), _ predicate: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !(await predicate()) {
            guard ContinuousClock.now < deadline else {
                throw WakePhaseTimeout(phase: phase, elapsedNS: clock.now().elapsedNS, sleeps: clock.sleepDescription)
            }
            try await Task.sleep(for: .milliseconds(pollDelayMS))
        }
    }
    func publishSnapshot(_ phase: String, beforeMS: Int64, waitForSampling: Bool = true) async throws {
        try await wait(phase + "-publisher-registration") { clock.nextSnapshotDeadlineNS != nil }
        let target = try #require(clock.nextSnapshotDeadlineNS)
        try #require(target < beforeMS * 1_000_000, "Publishing must not start the next optional probe")
        clock.advance(to: Fixtures.timestamp(ms: target / 1_000_000))
        try await wait(phase + "-snapshot", timeout: .seconds(2)) { await snapshots.latestElapsedNS >= target }
        if waitForSampling { try await wait(phase + "-sampling-callback") { clock.nextSamplingDeadlineNS != nil } }
    }
}

private struct WakePhaseTimeout: Error, CustomStringConvertible {
    let phase: String
    let elapsedNS: Int64
    let sleeps: String
    var description: String { "Wake phase timed out: \(phase), elapsed=\(elapsedNS), sleeps=\(sleeps)" }
}
