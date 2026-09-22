import Foundation
import Testing
@testable import SensorRuntime
@testable import TemperatureCore

@Suite(.serialized) struct MonitorIntegrationTests {
    @Test func schedulingScriptMatchesControlledPlan() async throws {
        let fixture = try await ControllerFixture.make()
        try await fixture.run([
            TimedControllerEvent(atMS: 0, event: .start(cpuPeriodMS: 200)),
            TimedControllerEvent(atMS: 200, event: .expectRead(kind: .cpu)),
            TimedControllerEvent(atMS: 210, event: .respond(allMembersCelsius: 80)),
        ])
        try await fixture.run([
            TimedControllerEvent(atMS: 250, event: .setCPUPeriod(ms: 500)),
            TimedControllerEvent(atMS: 400, event: .expectNoCPURead),
            TimedControllerEvent(atMS: 750, event: .expectRead(kind: .cpu)),
            TimedControllerEvent(atMS: 760, event: .respond(allMembersCelsius: 81)),
            TimedControllerEvent(atMS: 800, event: .stop),
        ])
        #expect(await fixture.client.readCount == 2)
        try await fixture.closeAndDeleteSession()
    }

    @Test func fiveMinuteHistoryUsesRealtimeMemoryPath() async throws {
        let fixture = try await ControllerFixture.make()
        try await fixture.run([
            TimedControllerEvent(atMS: 0, event: .start(cpuPeriodMS: 200)),
            TimedControllerEvent(atMS: 200, event: .expectRead(kind: .cpu)),
            TimedControllerEvent(atMS: 210, event: .respond(allMembersCelsius: 80)),
        ])

        let result = try await fixture.controller.history(
            HistoryRequest(
                seriesIDs: [fixture.seriesID],
                range: .fiveMinutes,
                asOfElapsedNS: 300_000_000,
                pointLimit: 100
            )
        )
        #expect(await fixture.client.readCount == 1)
        #expect(try await fixture.session.rows(in: "ema_samples") >= 1)
        #expect(result.layer == .ema)
        #expect(result.persistedThroughElapsedNS == nil)
        #expect(!result.points.isEmpty)
        await fixture.controller.stop()
        try await fixture.closeAndDeleteSession()
    }

    @Test func longHistoryUsesSQLiteQueryWithPersistedThrough() async throws {
        let fixture = try await ControllerFixture.make()
        try await fixture.run([
            TimedControllerEvent(atMS: 0, event: .start(cpuPeriodMS: 200)),
            TimedControllerEvent(atMS: 200, event: .expectRead(kind: .cpu)),
            TimedControllerEvent(atMS: 210, event: .respond(allMembersCelsius: 80)),
        ])

        fixture.clock.advance(to: Fixtures.timestamp(ms: 2_100))
        try await Task.sleep(nanoseconds: 50_000_000)
        let result = try await fixture.controller.history(
            HistoryRequest(
                seriesIDs: [fixture.seriesID],
                range: .oneHour,
                asOfElapsedNS: 2_100_000_000,
                pointLimit: 100
            )
        )
        #expect(result.layer == .oneSecond)
        if result.points.isEmpty {
            #expect(result.persistedThroughElapsedNS == nil)
        } else {
            #expect(result.persistedThroughElapsedNS != nil)
        }
        await fixture.controller.stop()
        try await fixture.closeAndDeleteSession()
    }

    @Test func supersededHistoryQueryIsCancelled() async throws {
        let fixture = try await ControllerFixture.make()
        try await fixture.run([
            TimedControllerEvent(atMS: 0, event: .start(cpuPeriodMS: 200)),
            TimedControllerEvent(atMS: 200, event: .expectRead(kind: .cpu)),
            TimedControllerEvent(atMS: 210, event: .respond(allMembersCelsius: 80)),
        ])
        try await populateDayHistoryBuckets(fixture: fixture, seriesID: fixture.seriesID)

        let seriesID = fixture.seriesID
        async let first = fixture.controller.history(
            HistoryRequest(
                seriesIDs: [seriesID],
                range: .oneDay,
                asOfElapsedNS: 86_400_000_000_000,
                pointLimit: 2000
            )
        )
        async let second = fixture.controller.history(
            HistoryRequest(
                seriesIDs: [seriesID],
                range: .oneHour,
                asOfElapsedNS: 300_000_000,
                pointLimit: 100
            )
        )

        do {
            _ = try await first
            Issue.record("expected superseded history failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .databaseRead)
            #expect(failure.underlyingCode == "superseded")
        }

        _ = try await second
        await fixture.controller.stop()
        try await fixture.closeAndDeleteSession()
    }

    @Test func snapshotsPublishAtMostEveryTwoHundredMilliseconds() async throws {
        let fixture = try await ControllerFixture.make()
        let snapshots = await fixture.controller.snapshots()
        let publishTimes = SnapshotCollector<Int64>()

        let consumer = Task {
            for await _ in snapshots {
                await publishTimes.append(fixture.clock.now().elapsedNS)
                if await publishTimes.count >= 3 {
                    break
                }
            }
        }

        try await fixture.run([
            TimedControllerEvent(atMS: 0, event: .start(cpuPeriodMS: 200)),
            TimedControllerEvent(atMS: 200, event: .expectRead(kind: .cpu)),
            TimedControllerEvent(atMS: 210, event: .respond(allMembersCelsius: 80)),
        ])

        for ms: Int64 in stride(from: 250, through: 900, by: 50) {
            fixture.clock.advance(to: Fixtures.timestamp(ms: ms))
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        consumer.cancel()
        let times = await publishTimes.values
        #expect(times.count >= 2)
        for index in 1..<times.count {
            #expect(times[index] - times[index - 1] >= 200_000_000)
        }
        await fixture.controller.stop()
        try await fixture.closeAndDeleteSession()
    }

    @Test func bufferingNewestSnapshotDropsIntermediateValues() async throws {
        let fixture = try await ControllerFixture.make()
        try await fixture.run([
            TimedControllerEvent(atMS: 0, event: .start(cpuPeriodMS: 200)),
            TimedControllerEvent(atMS: 200, event: .expectRead(kind: .cpu)),
            TimedControllerEvent(atMS: 210, event: .respond(allMembersCelsius: 70)),
        ])

        let snapshots = await fixture.controller.snapshots()
        let generations = SnapshotCollector<UInt64>()
        let consumer = Task {
            for await snapshot in snapshots {
                try? await Task.sleep(nanoseconds: 300_000_000)
                await generations.append(snapshot.generation)
                break
            }
        }

        for ms: Int64 in stride(from: 250, through: 850, by: 50) {
            fixture.clock.advance(to: Fixtures.timestamp(ms: ms))
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        try await Task.sleep(nanoseconds: 400_000_000)
        consumer.cancel()
        let observed = await generations.values
        #expect(observed.count == 1)
        #expect(observed[0] >= 1)
        await fixture.controller.stop()
        try await fixture.closeAndDeleteSession()
    }

    @Test func fullCPUSoftwareDataLoopPersistsRawMaxEMAAndHistory() async throws {
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
        #expect(try await fixture.session.rows(in: "sources") == 12)
        #expect(try await fixture.session.rows(in: "series") == 13)
        #expect(try await fixture.session.rows(in: "raw_samples") == 13)
        #expect(try await fixture.session.rows(in: "ema_samples") == 13)
        #expect(try await fixture.session.rows(in: "sample_members") == 12)
        #expect(try await fixture.session.rows(in: "committed_batches") == 1)

        let snapshots = await fixture.controller.snapshots()
        let snapshotCollector = SnapshotCollector<Snapshot>()
        let consumer = Task {
            for await snapshot in snapshots {
                await snapshotCollector.append(snapshot)
                if snapshot.generation >= 1 {
                    break
                }
            }
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        consumer.cancel()

        let captured = await snapshotCollector.values
        let snapshot = try #require(captured.last)
        #expect(snapshot.generation >= 1)
        let maxValue = try #require(
            snapshot.values.first { $0.definition.seriesID == cpuMaxSeriesID }
        )
        if case let .available(ema, _, _) = maxValue.state {
            #expect(ema.valueC == 95)
        } else {
            Issue.record("expected cpu max series to be available in snapshot")
        }

        let realtime = try await fixture.controller.history(
            HistoryRequest(
                seriesIDs: [cpuMaxSeriesID],
                range: .fiveMinutes,
                asOfElapsedNS: 250_000_000,
                pointLimit: 100
            )
        )
        #expect(realtime.layer == .ema)
        #expect(realtime.persistedThroughElapsedNS == nil)
        #expect(realtime.points.contains { $0.valueC == 95 })
        #expect(realtime.points.allSatisfy { $0.segment == 1 })

        await fixture.controller.stop()
        try await fixture.closeAndDeleteSession()
    }

    @Test func fullCPUSoftwareDataLoopReceiptMatchesPersistedRecords() async throws {
        let fixture = try await ControllerFixture.makeFullCPU()
        let memberValues = Array(repeating: 80.0, count: 12)

        try await fixture.run([
            TimedControllerEvent(atMS: 0, event: .start(cpuPeriodMS: 200)),
            TimedControllerEvent(atMS: 200, event: .expectRead(kind: .cpu)),
            TimedControllerEvent(atMS: 210, event: .respondMembers(celsius: memberValues)),
        ])

        let rawCount = try await fixture.session.rows(in: "raw_samples")
        let emaCount = try await fixture.session.rows(in: "ema_samples")
        let batchCount = try await fixture.session.rows(in: "committed_batches")
        #expect(batchCount == 1)
        #expect(rawCount == emaCount)
        #expect(rawCount == 13)

        try await fixture.run([
            TimedControllerEvent(atMS: 1_400, event: .expectRead(kind: .cpu)),
            TimedControllerEvent(atMS: 1_410, event: .respondMembers(celsius: memberValues)),
        ])
        #expect(await fixture.client.readCount == 2)
        #expect(try await fixture.session.rows(in: "raw_samples") == 26)
        #expect(try await fixture.session.rows(in: "committed_batches") == 2)

        await fixture.controller.stop()
        try await fixture.closeAndDeleteSession()
    }
}

private func populateDayHistoryBuckets(
    fixture: ControllerFixture,
    seriesID: SeriesID
) async throws {
    let chunkSize = 200
    var batchOrdinal = 900
    for startIndex in stride(from: 0, to: 8640, by: chunkSize) {
        var buckets: [Bucket] = []
        buckets.reserveCapacity(chunkSize)
        for offset in 0..<chunkSize {
            let index = startIndex + offset
            if index >= 8640 { break }
            let start = Int64(index) * 10 * 1_000_000_000
            let end = start + 10 * 1_000_000_000
            buckets.append(
                Bucket(
                    seriesID: seriesID,
                    segment: 1,
                    widthSeconds: 10,
                    startElapsedNS: start,
                    endElapsedNS: end,
                    minC: 49,
                    maxC: 50,
                    sumC: 50,
                    count: 1,
                    latestC: 50,
                    latestElapsedNS: start + 5 * 1_000_000_000,
                    latestSampleID: "integration-bucket-\(index)",
                    isPartial: false,
                    coverageNS: 10_000_000_000
                )
            )
        }
        let batch = PersistenceBatch(
            batchID: BatchID(Fixtures.uuid(batchOrdinal)),
            sources: [],
            definitions: [],
            segments: [],
            raw: [],
            ema: [],
            buckets: buckets,
            trends: [],
            gaps: []
        )
        batchOrdinal += 1
        _ = try await fixture.session.appendForTesting(batch)
    }
}

private actor SnapshotCollector<Element: Sendable> {
    private(set) var values: [Element] = []

    var count: Int {
        values.count
    }

    func append(_ value: Element) {
        values.append(value)
    }
}
