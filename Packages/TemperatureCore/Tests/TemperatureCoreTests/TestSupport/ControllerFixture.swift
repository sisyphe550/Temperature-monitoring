import Foundation
import Testing
@testable import SensorRuntime
@testable import TemperatureCore

enum ControllerScriptEvent: Equatable {
    case start(cpuPeriodMS: Int? = nil)
    case expectRead(kind: SamplingScheduleKind)
    case expectNoCPURead
    case respond(allMembersCelsius: Double)
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
            seriesID: seriesID
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

actor ScriptableSensorClient: SensorClient {
    private let clock: TestClock
    private let catalog: QualifiedSourceCatalog
    private var pendingResponses: [Double] = []
    private(set) var readCount = 0
    private(set) var lastReadKind: SamplingScheduleKind?

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
        while pendingResponses.isEmpty {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let celsius = pendingResponses.removeFirst()
        let finished = clock.now()
        let started = Timestamp(
            elapsedNS: finished.elapsedNS - Int64(request.requestedPeriodMS) * 1_000_000,
            wallUnixNS: finished.wallUnixNS - Int64(request.requestedPeriodMS) * 1_000_000
        )
        let readings = request.sourceIDs.map { sourceID in
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
            readings: readings
        )
    }

    func respond(allMembersCelsius: Double) {
        pendingResponses.append(allMembersCelsius)
    }

    func currentReadKind() -> SamplingScheduleKind? {
        lastReadKind
    }

    func close() async {}
}
