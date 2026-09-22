import Foundation
@testable import TemperatureCore

actor TestCommitCapability: PersistenceCommitCapability {
    private(set) var committed: [PersistenceBatch] = []
    private var snapshotGeneration: UInt64 = 0

    func commit(_ batch: PersistenceBatch, using lease: PersistenceLease) async throws -> ProcessingReceipt {
        _ = lease
        committed.append(batch)
        snapshotGeneration += 1
        let recordCount = batch.raw.count + batch.ema.count + batch.buckets.count + batch.trends.count + batch.gaps.count
        return ProcessingReceipt(
            batchID: batch.batchID,
            acceptedRecords: recordCount,
            snapshotGeneration: snapshotGeneration
        )
    }

    func committedBatch(for batchID: BatchID) -> PersistenceBatch? {
        committed.first { $0.batchID == batchID }
    }
}

struct ProcessorFixture {
    let engine: MonitorEngine
    let clock: TestClock
    let commit: TestCommitCapability
    let seriesID: SeriesID
    let sessionID: SessionID

    static func make(cpuMembers: Int = 1) async throws -> ProcessorFixture {
        let sessionID = try SessionID(validating: "00000000-0000-4000-8000-000000000401")
        let seriesID = SeriesID(Fixtures.uuid(101))
        let clock = TestClock(now: Fixtures.timestamp(ms: 0))
        let commit = TestCommitCapability()
        let configuration = try Configuration.bundledDefaults()
        var definitions: [SeriesDefinition] = []
        var memberSourceIDs: [SourceID] = []
        for index in 1...cpuMembers {
            memberSourceIDs.append(SourceID(Fixtures.uuid(index)))
        }
        definitions.append(
            SeriesDefinition(
                seriesID: seriesID,
                metricID: try MetricID(validating: "fixture.cpu"),
                definitionVersion: 1,
                kind: .cpuZone,
                displayName: "测试来源",
                memberSourceIDs: memberSourceIDs,
                formula: cpuMembers == 1 ? .identity : .maximum
            )
        )
        let engine = MonitorEngine(
            clock: clock,
            commit: commit,
            session: SessionMetadata(
                sessionID: sessionID,
                startedWallUnixNS: 1_700_000_000_000_000_000,
                model: "Mac16,13",
                osBuild: "24G419",
                appVersion: "0.1.0-test"
            ),
            configuration: configuration,
            definitions: definitions,
            cpuPeriodMS: configuration.cpuDefaultMS
        )
        return ProcessorFixture(
            engine: engine,
            clock: clock,
            commit: commit,
            seriesID: seriesID,
            sessionID: sessionID
        )
    }

    func lease(owner: PersistenceOwner, generation: UInt64) -> PersistenceLease {
        PersistenceLease(
            reservationID: UUID(),
            owner: owner,
            generation: generation,
            maxRecords: 512,
            maxBytes: 32 * 1024 * 1024
        )
    }

    func committedBatch(for receipt: ProcessingReceipt) async -> PersistenceBatch? {
        await commit.committedBatch(for: receipt.batchID)
    }

    @discardableResult
    func accept(_ batch: ReadBatch, lease: PersistenceLease) async throws -> ProcessingReceipt {
        let receipt = try await engine.accept(batch, lease: lease)
        if let latest = batch.readings.map(\.finished.elapsedNS).max() {
            clock.advance(to: Fixtures.timestamp(ms: latest / 1_000_000))
        }
        return receipt
    }

    func rawSamples(nowMS: Int64) async -> [Sample] {
        await engine.rawSamples(for: seriesID, nowElapsedNS: nowMS * 1_000_000)
    }
}
