import Foundation
import Testing
@testable import SensorRuntime
@testable import TemperatureCore

@Suite(.serialized) struct OptionalGenerationRecoveryRegressionTests {
    @Test func sourceGenerationChangeRequiresThreeNewOptionalReceipts() async throws {
        let profile = try Configuration.bundledProfile()
        let configuration = try Configuration.bundledDefaults()
        let clock = TestClock(now: Fixtures.timestamp(ms: 0))
        let sources = profile.cpuKeys.map { DiscoveredSource(transportHandle: "smc:\($0)", provider: .smc, rawKey: $0,
            registryID: "review-\($0)", encoding: profile.expectedSMCEncoding, byteCount: profile.expectedSMCSizeBytes) }
            + [DiscoveredSource(transportHandle: "nvme:12345", provider: .nvme, rawKey: "TEMPERATURE", registryID: "12345",
                encoding: "uint16_le_kelvin", byteCount: 2, physicalInterconnectLocation: "Internal", interconnectLookupStatus: .found)]
        let transport = GenerationProbeTransport(clock: clock, sources: sources)
        let client = QualifiedSensorClient(transport: transport, registry: ProfileRegistry(profile: profile))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OptionalGeneration-\(UUID())")
        let session = SessionPersistenceActor(databaseURL: root.appendingPathComponent("monitor.sqlite"))
        let controller = SessionMonitorController(clock: clock, client: client, session: session,
            sessionMetadata: SessionMetadata(sessionID: SessionID(UUID()), startedWallUnixNS: 1, model: "Mac16,13", osBuild: "24G419", appVersion: "review"), configuration: configuration)
        let snapshots = GenerationSnapshotLog()
        let stream = await controller.snapshots()
        let observer = Task { for await snapshot in stream { await snapshots.append(snapshot) } }
        var phase = "start"
        do {
            try await controller.start()
            phase = "initial-unavailable"
            print("GEN_BEGIN initial-unavailable elapsed=\(clock.now().elapsedNS)")
            try await generationAdvanceUntil(clock: clock) { let reads = await transport.optionalReads; let unavailable = await snapshots.hasUnavailableSSD; return reads >= 4 && unavailable }
            // Complete exactly two successful, committed probes of generation 1.
            clock.advance(to: Fixtures.timestamp(ms: clock.now().elapsedNS / 1_000_000 + 60_000))
            phase = "old-generation-two-probes"
            print("GEN_BEGIN old-generation-two-probes elapsed=\(clock.now().elapsedNS)")
            try await generationAdvanceUntil(clock: clock) { await transport.optionalReads >= 6 }
            try await Task.sleep(for: .milliseconds(40))
            #expect(await transport.optionalReads == 6)
            #expect(await snapshots.hasUnavailableSSD)
            await transport.armCPUTimeout()
            phase = "new-generation-first-probe"
            print("GEN_BEGIN new-generation-first-probe elapsed=\(clock.now().elapsedNS)")
            try await generationAdvanceUntil(clock: clock) { let generation = await transport.discoverCount; let reads = await transport.newOptionalReads; return generation == 2 && reads >= 1 }
            try await Task.sleep(for: .milliseconds(40))
            #expect(await transport.newOptionalReads == 1)
            clock.advance(to: Fixtures.timestamp(ms: clock.now().elapsedNS / 1_000_000 + 200))
            phase = "snapshot-after-new-first"
            print("GEN_BEGIN snapshot-after-new-first elapsed=\(clock.now().elapsedNS)")
            try await generationAwaitSnapshot(clock: clock, snapshots: snapshots)
            #expect(await transport.newOptionalReads == 1)
            #expect(await snapshots.hasGeneration2SSD)
            let newCatalog = try ProfileRegistry(profile: profile).qualify(DiscoveredCatalog(generation: 2, sources: sources))
            let newSSD = try #require(SeriesCatalogBuilder.definitions(from: newCatalog).first { $0.kind == .ssd })
            let reader = try SQLiteStore(databaseURL: root.appendingPathComponent("monitor.sqlite"))
            let committedNewReads = try reader.queryInt64("SELECT COUNT(*) FROM raw_samples WHERE series_id = '\(newSSD.seriesID.rawValue)'")
            reader.close()
            #expect(committedNewReads == 1)
            #expect(await snapshots.newSSDIsUnavailable, "Generation 2 SSD must require three new committed reads, rather than inheriting two successes from generation 1")
            #expect(await controller.lastAcceptFailure() == nil)
            phase = "new-generation-second-probe"
            print("GEN_BEGIN new-generation-second-probe elapsed=\(clock.now().elapsedNS)")
            try await generationAdvanceUntil(clock: clock) { await transport.newOptionalReads >= 2 }
            clock.advance(to: Fixtures.timestamp(ms: clock.now().elapsedNS / 1_000_000 + 200))
            phase = "snapshot-after-new-second"
            print("GEN_BEGIN snapshot-after-new-second elapsed=\(clock.now().elapsedNS)")
            try await generationAwaitSnapshot(clock: clock, snapshots: snapshots)
            #expect(await transport.newOptionalReads == 2)
            #expect(await snapshots.newSSDIsUnavailable)
            phase = "new-generation-third-probe"
            print("GEN_BEGIN new-generation-third-probe elapsed=\(clock.now().elapsedNS)")
            try await generationAdvanceUntil(clock: clock) { await transport.newOptionalReads >= 3 }
            clock.advance(to: Fixtures.timestamp(ms: clock.now().elapsedNS / 1_000_000 + 200))
            phase = "snapshot-after-new-third"
            print("GEN_BEGIN snapshot-after-new-third elapsed=\(clock.now().elapsedNS)")
            try await generationAwaitSnapshot(clock: clock, snapshots: snapshots)
            #expect(await transport.newOptionalReads == 3)
            #expect(await snapshots.newSSDIsAvailable)
            await controller.stop()
            await observer.value
        } catch {
            print("GEN_TIMEOUT phase=\(phase) elapsed=\(clock.now().elapsedNS) optional=\(await transport.optionalReads) newOptional=\(await transport.newOptionalReads) discoveries=\(await transport.discoverCount) snapshot=\(await snapshots.latestElapsedNS) unavailable=\(await snapshots.hasUnavailableSSD) newUnavailable=\(await snapshots.newSSDIsUnavailable) pending=\(clock.pendingSleepDeadlinesForTesting) error=\(error)")
            await controller.stop()
            observer.cancel()
            await observer.value
            throw error
        }
    }
}

private actor GenerationProbeTransport: SensorTransport {
    let clock: TestClock
    let sources: [DiscoveredSource]
    private(set) var discoverCount = 0
    private(set) var optionalReads = 0
    private(set) var newOptionalReads = 0
    private var shouldFailCPU = false
    init(clock: TestClock, sources: [DiscoveredSource]) { self.clock = clock; self.sources = sources }
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

private func generationAdvanceUntil(clock: TestClock, predicate: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(4)
    while !(await predicate()) {
        guard ContinuousClock.now < deadline else { throw CocoaError(.fileReadUnknown) }
        clock.advance(to: Fixtures.timestamp(ms: clock.now().elapsedNS / 1_000_000 + 25))
        let modelDelayMS = Int(ProcessInfo.processInfo.environment["TM_GENERATION_POLL_DELAY_MS"] ?? "5") ?? 5
        try await Task.sleep(for: .milliseconds(modelDelayMS))
    }
}

private func generationAwaitSnapshot(clock: TestClock, snapshots: GenerationSnapshotLog) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while await snapshots.latestElapsedNS < clock.now().elapsedNS {
        guard ContinuousClock.now < deadline else { throw CocoaError(.fileReadUnknown) }
        try await Task.sleep(for: .milliseconds(2))
    }
}
