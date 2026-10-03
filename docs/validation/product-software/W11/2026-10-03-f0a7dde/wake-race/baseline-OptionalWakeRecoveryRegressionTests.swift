import Foundation
import Testing
@testable import SensorRuntime
@testable import TemperatureCore

@Suite(.serialized) struct OptionalWakeRecoveryRegressionTests {
    @Test func wakeRediscoveryCanRecoverPreviouslyUnavailableOptionalSource() async throws {
        let profile = try Configuration.bundledProfile()
        let configuration = try Configuration.bundledDefaults()
        let clock = TestClock(now: Fixtures.timestamp(ms: 0))
        let sources = profile.cpuKeys.map { DiscoveredSource(transportHandle: "smc:\($0)", provider: .smc, rawKey: $0,
            registryID: "review-\($0)", encoding: profile.expectedSMCEncoding, byteCount: profile.expectedSMCSizeBytes) }
            + [DiscoveredSource(transportHandle: "nvme:12345", provider: .nvme, rawKey: "TEMPERATURE", registryID: "12345",
                encoding: "uint16_le_kelvin", byteCount: 2, physicalInterconnectLocation: "Internal", interconnectLookupStatus: .found)]
        let transport = WakeProbeTransport(clock: clock, sources: sources)
        let client = QualifiedSensorClient(transport: transport, registry: ProfileRegistry(profile: profile))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OptionalWake-\(UUID())")
        let session = SessionPersistenceActor(databaseURL: root.appendingPathComponent("monitor.sqlite"))
        let controller = SessionMonitorController(clock: clock, client: client, session: session,
            sessionMetadata: SessionMetadata(sessionID: SessionID(UUID()), startedWallUnixNS: 1, model: "Mac16,13", osBuild: "24G419", appVersion: "review"), configuration: configuration)
        let snapshots = WakeSnapshotLog()
        let stream = await controller.snapshots()
        let observer = Task { for await snapshot in stream { await snapshots.append(snapshot) } }
        do {
            try await controller.start()
            try await wakeAdvanceUntil(clock: clock) { let reads = await transport.optionalReads; let unavailable = await snapshots.hasUnavailableSSD; return reads >= 4 && unavailable }
            #expect(await transport.optionalReads == 4)
            try await controller.suspendForSleep()
            clock.advance(to: Fixtures.timestamp(ms: clock.now().elapsedNS / 1_000_000 + 2000))
            try await controller.resumeAfterWake()
            try await wakeAdvanceUntil(clock: clock) { await transport.newOptionalReads >= 3 }
            clock.advance(to: Fixtures.timestamp(ms: clock.now().elapsedNS / 1_000_000 + 200))
            try await wakeAwaitSnapshot(clock: clock, snapshots: snapshots)
            #expect(await transport.newOptionalReads == 3)
            #expect(await snapshots.hasGeneration2SSD)
            let newCatalog = try ProfileRegistry(profile: profile).qualify(DiscoveredCatalog(generation: 2, sources: sources))
            let newSSD = try #require(SeriesCatalogBuilder.definitions(from: newCatalog).first { $0.kind == .ssd })
            let reader = try SQLiteStore(databaseURL: root.appendingPathComponent("monitor.sqlite"))
            let committedNewReads = try reader.queryInt64("SELECT COUNT(*) FROM raw_samples WHERE series_id = '\(newSSD.seriesID.rawValue)'")
            reader.close()
            #expect(committedNewReads == 3)
            #expect(await snapshots.newSSDIsAvailable, "An optional source requalified after wake and three new committed readings must leave its old unavailable state")
            #expect(await controller.lastAcceptFailure() == nil)
            await controller.stop()
            await observer.value
        } catch {
            await controller.stop()
            observer.cancel()
            await observer.value
            throw error
        }
    }
}

private actor WakeProbeTransport: SensorTransport {
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

private func wakeAdvanceUntil(clock: TestClock, predicate: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(4)
    while !(await predicate()) {
        guard ContinuousClock.now < deadline else { throw CocoaError(.fileReadUnknown) }
        clock.advance(to: Fixtures.timestamp(ms: clock.now().elapsedNS / 1_000_000 + 25))
        try await Task.sleep(for: .milliseconds(5))
    }
}

private func wakeAwaitSnapshot(clock: TestClock, snapshots: WakeSnapshotLog) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while await snapshots.latestElapsedNS < clock.now().elapsedNS {
        guard ContinuousClock.now < deadline else { throw CocoaError(.fileReadUnknown) }
        try await Task.sleep(for: .milliseconds(2))
    }
}
