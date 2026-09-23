import Foundation
import Testing
@testable import SensorRuntime
@testable import TemperatureCore

enum ControllerScriptEvent: Equatable {
    case start(cpuPeriodMS: Int? = nil)
    case expectRead(kind: SamplingScheduleKind)
    case expectNoCPURead
    case respond(allMembersCelsius: Double)
    case respondMembers(celsius: [Double])
    case setCPUPeriod(ms: Int)
    case stop
}

struct TimedControllerEvent: Equatable {
    let atMS: Int64
    let event: ControllerScriptEvent
}

struct ControllerFixture {
    let controller: SessionMonitorController
    let clock: TestClock
    let client: ScriptableSensorClient
    let session: SessionPersistenceActor
    let seriesID: SeriesID
    let cpuMaxSeriesID: SeriesID?
    let cpuMemberCount: Int

    static var fullCPUMaxSeriesID: SeriesID {
        get throws {
            try SeriesID(validating: "00000000-0000-4000-8000-000000000200")
        }
    }

    static func make() async throws -> ControllerFixture {
        let clock = TestClock(now: Fixtures.timestamp(ms: 0))
        let sourceID = SourceID(Fixtures.uuid(10))
        let seriesID = try SeriesID(validating: sourceID.rawValue)
        let catalog = QualifiedSourceCatalog(
            generation: 1,
            available: [
                QualifiedSource(
                    sourceID: sourceID,
                    transportHandle: "mock:cpu-0",
                    provider: .smc,
                    rawKey: "Tp01",
                    registryID: nil,
                    connectionGeneration: 1,
                    kind: .cpuZone,
                    encoding: "flt ",
                    unitEvidence: "test",
                    evidence: .targetQualified,
                    mappingVersion: "test-v1"
                )
            ],
            unavailable: []
        )
        let client = ScriptableSensorClient(clock: clock, catalog: catalog)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ControllerFixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = SessionPersistenceActor(
            databaseURL: directory.appendingPathComponent("session.sqlite")
        )
        let configuration = try Configuration.bundledDefaults()
        let controller = SessionMonitorController(
            clock: clock,
            client: client,
            session: session,
            sessionMetadata: try testSessionMetadata(),
            configuration: configuration
        )
        return ControllerFixture(
            controller: controller,
            clock: clock,
            client: client,
            session: session,
            seriesID: seriesID,
            cpuMaxSeriesID: nil,
            cpuMemberCount: 1
        )
    }

    static func makeFullCPU() async throws -> ControllerFixture {
        let clock = TestClock(now: Fixtures.timestamp(ms: 0))
        let profile = try Configuration.bundledProfile()
        let discovered = try FullCPUQualifyFixture.fullCPUCatalog(for: profile)
        let catalog = try ProfileRegistry(profile: profile).qualify(discovered)
        let firstSource = try #require(catalog.available.first)
        let seriesID = try SeriesID(validating: firstSource.sourceID.rawValue)
        let client = ScriptableSensorClient(clock: clock, catalog: catalog)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ControllerFixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = SessionPersistenceActor(
            databaseURL: directory.appendingPathComponent("session.sqlite")
        )
        let configuration = try Configuration.bundledDefaults()
        let controller = SessionMonitorController(
            clock: clock,
            client: client,
            session: session,
            sessionMetadata: try testSessionMetadata(),
            configuration: configuration
        )
        return ControllerFixture(
            controller: controller,
            clock: clock,
            client: client,
            session: session,
            seriesID: seriesID,
            cpuMaxSeriesID: try fullCPUMaxSeriesID,
            cpuMemberCount: catalog.available.filter { $0.kind == .cpuZone }.count
        )
    }

    func run(_ script: [TimedControllerEvent]) async throws {
        for timed in script.sorted(by: { $0.atMS < $1.atMS }) {
            clock.advance(to: Fixtures.timestamp(ms: timed.atMS))
            switch timed.event {
            case let .start(cpuPeriodMS):
                try await controller.start()
                if let cpuPeriodMS {
                    try await controller.setCPUPeriod(milliseconds: cpuPeriodMS)
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            case let .expectRead(kind):
                let readsBefore = await client.readCount
                try await waitUntil(timeoutMS: 500) {
                    let count = await client.readCount
                    let readKind = await client.currentReadKind()
                    return count > readsBefore && readKind == kind
                }
            case .expectNoCPURead:
                let readsBefore = await client.readCount
                try await Task.sleep(nanoseconds: 30_000_000)
                if await client.readCount != readsBefore {
                    Issue.record("unexpected cpu read while none was expected")
                }
            case let .respond(celsius):
                await client.respond(allMembersCelsius: celsius)
                try await Task.sleep(nanoseconds: 50_000_000)
            case let .respondMembers(celsius):
                await client.respond(membersCelsius: celsius)
                try await Task.sleep(nanoseconds: 50_000_000)
            case let .setCPUPeriod(ms):
                try await controller.setCPUPeriod(milliseconds: ms)
            case .stop:
                await controller.stop()
            }
        }
    }

    func closeAndDeleteSession() async throws {
        try await session.closeAndDeleteSession()
    }

    private static func testSessionMetadata() throws -> SessionMetadata {
        SessionMetadata(
            sessionID: try SessionID(validating: "00000000-0000-4000-8000-000000000801"),
            startedWallUnixNS: 1_700_000_000_000_000_000,
            model: "Mac16,13",
            osBuild: "24G419",
            appVersion: "0.1.0-test"
        )
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
        Issue.record("controller script condition not met before timeout")
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

actor ScriptableSensorClient: SensorClient {
    private let clock: TestClock
    private let catalog: QualifiedSourceCatalog
    private var pendingResponses: [Double] = []
    private var pendingMemberResponses: [[Double]] = []
    private(set) var readCount = 0
    private(set) var lastReadKind: SamplingScheduleKind?
    private(set) var lastReadSourceCount = 0

    init(clock: TestClock, catalog: QualifiedSourceCatalog) {
        self.clock = clock
        self.catalog = catalog
    }

    func discover() async throws -> QualifiedSourceCatalog {
        catalog
    }

    func read(_ request: ReadRequest) async throws -> ReadBatch {
        readCount += 1
        let kind: SamplingScheduleKind
        if catalog.available.contains(where: { $0.kind == .cpuZone && request.sourceIDs.contains($0.sourceID) }) {
            kind = .cpu
        } else if catalog.available.contains(where: { $0.kind == .ssd && request.sourceIDs.contains($0.sourceID) }) {
            kind = .ssd
        } else {
            kind = .battery
        }
        lastReadKind = kind
        lastReadSourceCount = request.sourceIDs.count
        while pendingResponses.isEmpty && pendingMemberResponses.isEmpty {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let memberValues: [Double]
        if let members = pendingMemberResponses.first {
            pendingMemberResponses.removeFirst()
            memberValues = members
        } else {
            let celsius = pendingResponses.removeFirst()
            memberValues = Array(repeating: celsius, count: request.sourceIDs.count)
        }
        let finished = clock.now()
        let started = Timestamp(
            elapsedNS: finished.elapsedNS - Int64(request.requestedPeriodMS) * 1_000_000,
            wallUnixNS: finished.wallUnixNS - Int64(request.requestedPeriodMS) * 1_000_000
        )
        let readings = zip(request.sourceIDs, memberValues).map { sourceID, celsius in
            Reading(
                sourceID: sourceID,
                started: started,
                finished: finished,
                outcome: .success(valueC: celsius, sourceWallUnixNS: nil, freshness: .unknown)
            )
        }
        return ReadBatch(
            requestID: request.requestID,
            generation: catalog.generation,
            requestedPeriodMS: request.requestedPeriodMS,
            readings: readings
        )
    }

    func respond(allMembersCelsius: Double) {
        pendingResponses.append(allMembersCelsius)
    }

    func respond(membersCelsius: [Double]) {
        pendingMemberResponses.append(membersCelsius)
    }

    func currentReadKind() -> SamplingScheduleKind? {
        lastReadKind
    }

    func close() async {}
}
