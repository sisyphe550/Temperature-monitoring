import Foundation
import Testing
@testable import SensorRuntime
@testable import TemperatureCore

@Suite("EndToEndTests")
struct EndToEndTests {
    @Test func fullCPURawToHistorySoftwareLoop() async throws {
        let fixture = try await ControllerFixture.makeFullCPU()
        let cpuMaxSeriesID = try #require(fixture.cpuMaxSeriesID)
        #expect(fixture.cpuMemberCount == 12)

        var memberValues = Array(repeating: 70.0, count: 12)
        memberValues[0] = 95.0

        try await fixture.run([
            TimedControllerEvent(atMS: 0, event: .start(cpuPeriodMS: 200)),
            TimedControllerEvent(atMS: 200, event: .expectRead(kind: .cpu)),
            TimedControllerEvent(atMS: 210, event: .respondMembers(celsius: memberValues)),
        ])

        #expect(await fixture.client.readCount == 1)
        #expect(await fixture.client.lastReadSourceCount == 12)
        #expect(try await fixture.session.rows(in: "raw_samples") == 13)
        #expect(try await fixture.session.rows(in: "ema_samples") == 13)
        #expect(try await fixture.session.rows(in: "committed_batches") == 1)

        let history = try await fixture.controller.history(
            HistoryRequest(
                seriesIDs: [cpuMaxSeriesID],
                range: .fiveMinutes,
                asOfElapsedNS: 250_000_000,
                pointLimit: 100
            )
        )
        #expect(history.layer == .ema)
        #expect(history.points.contains { $0.valueC == 95 })

        await fixture.controller.stop()
        try await fixture.closeAndDeleteSession()
    }

    @Test func sessionCloseRemovesDatabaseSidecars() async throws {
        let fixture = try await TemporaryStoreFixture.make()
        _ = try await fixture.appendForTesting(
            try Fixtures.persistence(id: BatchID(Fixtures.uuid(901)), value: 80, ms: 100)
        )

        let databaseURL = fixture.databaseURL
        let walURL = URL(fileURLWithPath: databaseURL.path + "-wal")
        let shmURL = URL(fileURLWithPath: databaseURL.path + "-shm")

        try await fixture.closeAndDeleteSession()

        let fileManager = FileManager.default
        #expect(fileManager.fileExists(atPath: databaseURL.path) == false)
        #expect(fileManager.fileExists(atPath: walURL.path) == false)
        #expect(fileManager.fileExists(atPath: shmURL.path) == false)
    }

    @Test func gapBatchSurvivesPersistenceRoundTrip() async throws {
        let fixture = try await TemporaryStoreFixture.make()
        _ = try await fixture.appendForTesting(
            try Fixtures.persistence(id: BatchID(Fixtures.uuid(902)), value: 70, ms: 50)
        )
        _ = try await fixture.appendForTesting(
            try gapBatch(
                batchID: BatchID(Fixtures.uuid(903)),
                gapID: GapID(Fixtures.uuid(904)),
                endedElapsedNS: nil
            )
        )
        _ = try await fixture.appendForTesting(
            try gapBatch(
                batchID: BatchID(Fixtures.uuid(905)),
                gapID: GapID(Fixtures.uuid(904)),
                endedElapsedNS: 200_000_000
            )
        )
        #expect(try await fixture.rows(in: "gaps") == 1)
        try await fixture.closeAndDeleteSession()
    }

    @Test func databaseBackpressureBlocksAdditionalReserve() async throws {
        let configuration = try makeWriterConfiguration(
            maxRecords: 8,
            pauseAt: 3,
            resumeBelow: 1
        )
        let fixture = try await EndToEndPersistenceLeaseFixture.make(configuration: configuration)
        let owner = PersistenceOwner.request(RequestID(Fixtures.uuid(906)))

        for generation in 1...3 {
            _ = try await fixture.session.reserve(
                owner: owner,
                generation: UInt64(generation),
                maxRecords: 1,
                maxBytes: 1024
            )
        }
        #expect(await fixture.session.isBackpressureLatchedForTesting)

        do {
            _ = try await fixture.session.reserve(
                owner: owner,
                generation: 4,
                maxRecords: 1,
                maxBytes: 1024
            )
            Issue.record("expected database backpressure failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .databaseBackpressure)
        }
    }

    @Test func transientDatabaseBusyUsesRetryPolicy() throws {
        let policy = try RetryPolicy(configuration: Configuration.bundledDefaults())
        #expect(policy.isRetryable(busyFailure(), domain: .database))
    }
}

@Suite("TC-UPSTREAM-BOUNDARY")
struct UpstreamBoundaryTests {
    @Test func twelveQualifiedSourcesDoNotInferTenPhysicalCores() throws {
        let profile = try Configuration.bundledProfile()
        let catalog = try FullCPUQualifyFixture.fullCPUCatalog(for: profile)
        let qualified = try ProfileRegistry(profile: profile).qualify(catalog)
        #expect(qualified.available.count == 12)
        #expect(MetricResolver.infersPhysicalCoreCount(from: qualified.available.count) == nil)
    }

    @Test func distinctHIDRegistryIDsAreNotMerged() throws {
        let profile = try Configuration.bundledProfile()
        let catalog = DiscoveredCatalog(
            generation: 1,
            sources: [
                DiscoveredSource(
                    transportHandle: "hid:0",
                    provider: .hid,
                    rawKey: "eACC CPU",
                    registryID: "00000000-0000-4000-8000-000000000101",
                    encoding: "event",
                    byteCount: 0
                ),
                DiscoveredSource(
                    transportHandle: "hid:1",
                    provider: .hid,
                    rawKey: "eACC CPU",
                    registryID: "00000000-0000-4000-8000-000000000102",
                    encoding: "event",
                    byteCount: 0
                ),
            ]
        )
        let qualified = try ProfileRegistry(profile: profile).qualify(catalog)
        let hidRecords = qualified.unavailable.filter { $0.provider == .hid }
        #expect(hidRecords.count == 2)
        #expect(Set(hidRecords.compactMap(\.registryID)).count == 2)
    }

    @Test func missingHIDEventDoesNotFabricateZeroCelsius() {
        #expect(Registry.hidTemperatureC(readStatus: -1, value: 0) == nil)
        #expect(SensorDecoding.nvmeTemperatureC(kelvin: 0) == nil)
    }

    @Test func upstreamRollbackDoesNotReplayOldSample() async throws {
        let fixture = try await ProcessorFixture.make()
        let firstID = RequestID(Fixtures.uuid(910))
        let secondID = RequestID(Fixtures.uuid(911))

        _ = try await fixture.accept(
            Fixtures.read(id: firstID, ms: 100, values: [80]),
            lease: fixture.lease(owner: .request(firstID), generation: 1)
        )
        let receipt = try await fixture.accept(
            Fixtures.read(id: secondID, ms: 50, values: [79]),
            lease: fixture.lease(owner: .request(secondID), generation: 1)
        )

        let committed = try #require(await fixture.committedBatch(for: receipt))
        #expect(committed.raw.isEmpty)
        #expect(await fixture.rawSamples(nowMS: 100).count == 1)
    }

    @Test func sensorBridgeSourceContainsNoWriteOrPrivilegeSymbols() throws {
        let source = try sensorBridgeSource()
        let forbidden = [
            "command = 6",
            "command = 7",
            "command=6",
            "command=7",
            "AuthorizationExecute",
            "setuid",
            "system(",
            "popen(",
            "NSTask",
            "SMSet",
            "AppleSMCForce",
            "kSMCSupervisor",
        ]
        for token in forbidden {
            #expect(!source.contains(token), "forbidden token found: \(token)")
        }
    }
}

private enum FullCPUQualifyFixture {
    static func fullCPUCatalog(for profile: SensorProfile) throws -> DiscoveredCatalog {
        let sources = profile.cpuKeys.map { key in
            DiscoveredSource(
                transportHandle: "smc:\(key)",
                provider: .smc,
                rawKey: key,
                registryID: "reg-\(key)",
                encoding: profile.expectedSMCEncoding,
                byteCount: profile.expectedSMCSizeBytes
            )
        }
        return DiscoveredCatalog(generation: 1, sources: sources)
    }
}

private struct EndToEndPersistenceLeaseFixture {
    let session: SessionPersistenceActor

    static func make(configuration: RuntimeConfiguration) async throws -> EndToEndPersistenceLeaseFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EndToEndLeaseFixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("session.sqlite")
        let session = SessionPersistenceActor(databaseURL: databaseURL, configuration: configuration)
        try await session.open(
            SessionMetadata(
                sessionID: try SessionID(validating: "00000000-0000-4000-8000-000000000906"),
                startedWallUnixNS: 1_700_000_000_000_000_000,
                model: "Mac16,13",
                osBuild: "24G419",
                appVersion: "0.1.0-test"
            )
        )
        return EndToEndPersistenceLeaseFixture(session: session)
    }
}

private func busyFailure() -> MonitorFailure {
    MonitorFailure(
        code: .databaseOpen,
        severity: .fatal,
        component: "SQLiteStore",
        operation: "open",
        retryCount: 0,
        sourceID: nil,
        underlyingCode: "busy"
    )
}

private func gapBatch(
    batchID: BatchID,
    gapID: GapID,
    endedElapsedNS: Int64?
) throws -> PersistenceBatch {
    PersistenceBatch(
        batchID: batchID,
        sources: [],
        definitions: [],
        segments: [],
        raw: [],
        ema: [],
        buckets: [],
        trends: [],
        gaps: [
            Gap(
                gapID: gapID,
                seriesID: SeriesID(Fixtures.uuid(101)),
                startedElapsedNS: 100_000_000,
                endedElapsedNS: endedElapsedNS,
                reason: .readFailure
            )
        ]
    )
}

private func sensorBridgeSource() throws -> String {
    var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while url.path != "/" {
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
            let source = url.appendingPathComponent("Sources/SensorBridge/SensorBridge.c")
            return try String(contentsOf: source, encoding: .utf8)
        }
        url.deleteLastPathComponent()
    }
    throw EndToEndTestError.missingBridgeSource
}

private enum EndToEndTestError: Error {
    case missingBridgeSource
}

private func makeWriterConfiguration(
    maxRecords: Int,
    pauseAt: Int,
    resumeBelow: Int
) throws -> RuntimeConfiguration {
    let defaults = try Configuration.bundledDefaults()
    let data = try JSONEncoder().encode(defaults)
    guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw ConfigurationError.invalidValue("writer_max_records")
    }
    object["writer_max_records"] = maxRecords
    object["writer_pause_at_records"] = pauseAt
    object["writer_resume_below_records"] = resumeBelow
    let patched = try JSONSerialization.data(withJSONObject: object)
    return try JSONDecoder().decode(RuntimeConfiguration.self, from: patched)
}
