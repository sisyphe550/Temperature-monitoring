import Foundation
import Testing
@testable import TemperatureCore

@Suite struct TrendTests {
    @Test func stableTrendAtTwoHundredthsPerSecond() throws {
        let calculator = try makeCalculator()
        let seriesID = SeriesID(Fixtures.uuid(101))
        let points = emaPoints(
            seriesID: seriesID,
            segment: 1,
            values: [(0, 20.0), (4000, 20.08), (8000, 20.16)]
        )
        let trend = calculator.compute(
            seriesID: seriesID,
            segment: 1,
            kind: .cpuMain,
            emaSamples: points,
            at: Fixtures.timestamp(ms: 8000)
        )
        #expect(trend.direction == .stable)
        #expect(abs((try #require(trend.slopeCPerSecond)) - 0.02) < 1e-6)
    }

    @Test func risingTrendAboveStableBand() throws {
        let calculator = try makeCalculator()
        let seriesID = SeriesID(Fixtures.uuid(101))
        let points = emaPoints(
            seriesID: seriesID,
            segment: 1,
            values: [(0, 20.0), (4000, 20.12), (8000, 20.24)]
        )
        let trend = calculator.compute(
            seriesID: seriesID,
            segment: 1,
            kind: .cpuMain,
            emaSamples: points,
            at: Fixtures.timestamp(ms: 8000)
        )
        #expect(trend.direction == .rising)
    }

    @Test func fallingTrendBelowStableBand() throws {
        let calculator = try makeCalculator()
        let seriesID = SeriesID(Fixtures.uuid(101))
        let points = emaPoints(
            seriesID: seriesID,
            segment: 1,
            values: [(0, 20.0), (4000, 19.88), (8000, 19.76)]
        )
        let trend = calculator.compute(
            seriesID: seriesID,
            segment: 1,
            kind: .cpuMain,
            emaSamples: points,
            at: Fixtures.timestamp(ms: 8000)
        )
        #expect(trend.direction == .falling)
    }

    @Test func twoPointsIsInsufficient() throws {
        let calculator = try makeCalculator()
        let seriesID = SeriesID(Fixtures.uuid(101))
        let points = emaPoints(
            seriesID: seriesID,
            segment: 1,
            values: [(0, 20.0), (4000, 20.08)]
        )
        let trend = calculator.compute(
            seriesID: seriesID,
            segment: 1,
            kind: .cpuMain,
            emaSamples: points,
            at: Fixtures.timestamp(ms: 4000)
        )
        #expect(trend.direction == .insufficient)
        #expect(trend.slopeCPerSecond == nil)
    }

    @Test func coverageBelowEightyPercentIsInsufficient() throws {
        let calculator = try makeCalculator()
        let seriesID = SeriesID(Fixtures.uuid(101))
        let points = emaPoints(
            seriesID: seriesID,
            segment: 1,
            values: [(0, 20.0), (3500, 20.07), (7990, 20.14)]
        )
        let trend = calculator.compute(
            seriesID: seriesID,
            segment: 1,
            kind: .cpuMain,
            emaSamples: points,
            at: Fixtures.timestamp(ms: 7990)
        )
        #expect(trend.direction == .insufficient)
    }

    @Test func gapSegmentExcludesOlderPoints() throws {
        let calculator = try makeCalculator()
        let seriesID = SeriesID(Fixtures.uuid(101))
        let points = emaPoints(
            seriesID: seriesID,
            segment: 1,
            values: [(0, 20.0), (4000, 20.08), (8000, 20.16)]
        ) + emaPoints(
            seriesID: seriesID,
            segment: 2,
            values: [(9000, 30.0), (13000, 30.08), (17000, 30.16)]
        )
        let trend = calculator.compute(
            seriesID: seriesID,
            segment: 2,
            kind: .cpuMain,
            emaSamples: points,
            at: Fixtures.timestamp(ms: 17000)
        )
        #expect(trend.direction == .stable)
        #expect(trend.pointCount == 3)
    }

    @Test func periodChangeDoesNotTriggerTimeoutGap() throws {
        let configuration = try Configuration.bundledDefaults()
        let deltaNS = Int64(500) * 1_000_000
        #expect(
            GapDetector.isTimeoutGap(
                deltaElapsedNS: deltaNS,
                previousPeriodMS: 200,
                currentPeriodMS: 1000,
                gapPeriodMultiplier: configuration.gapPeriodMultiplier,
                gapFloorMS: configuration.gapFloorMS
            ) == false
        )
    }

    @Test func gapReasonsPersistThroughMarkGap() async throws {
        for (index, reason) in GapReason.allCases.enumerated() {
            let fixture = try await ProcessorFixture.make()
            let gapID = GapID(Fixtures.uuid(700 + index))
            let gap = Gap(
                gapID: gapID,
                seriesID: fixture.seriesID,
                startedElapsedNS: 1_000_000_000,
                endedElapsedNS: nil,
                reason: reason
            )
            let receipt = try await fixture.markGap(gap, lease: fixture.lease(owner: .gap(gapID), generation: 1))
            let batch = try #require(await fixture.committedBatch(for: receipt))
            #expect(batch.gaps.count == 1)
            #expect(batch.gaps[0].reason == reason)
        }
    }

    @Test func closingGapIncrementsSegmentAndResetsEMA() async throws {
        let fixture = try await ProcessorFixture.make()
        let openID = GapID(Fixtures.uuid(710))
        let closeID = GapID(Fixtures.uuid(711))
        _ = try await fixture.markGap(
            Gap(
                gapID: openID,
                seriesID: fixture.seriesID,
                startedElapsedNS: 500_000_000,
                endedElapsedNS: nil,
                reason: .sleep
            ),
            lease: fixture.lease(owner: .gap(openID), generation: 1)
        )
        _ = try await fixture.markGap(
            Gap(
                gapID: closeID,
                seriesID: fixture.seriesID,
                startedElapsedNS: 500_000_000,
                endedElapsedNS: 2_000_000_000,
                reason: .sleep
            ),
            lease: fixture.lease(owner: .gap(closeID), generation: 1)
        )

        let requestID = RequestID(Fixtures.uuid(712))
        let receipt = try await fixture.accept(
            Fixtures.read(id: requestID, ms: 2500, values: [55]),
            lease: fixture.lease(owner: .request(requestID), generation: 1)
        )
        let batch = try #require(await fixture.committedBatch(for: receipt))
        #expect(batch.raw[0].segment == 2)
        #expect(batch.ema[0].valueC == 55)
    }

    @Test func rejectedCommitDoesNotAdvanceGapState() async throws {
        let commit = TestCommitCapability(rejectNextReceipt: true)
        let configuration = try Configuration.bundledDefaults()
        let engine = MonitorEngine(
            clock: TestClock(now: Fixtures.timestamp(ms: 0)),
            commit: commit,
            session: SessionMetadata(
                sessionID: try SessionID(validating: "00000000-0000-4000-8000-000000000402"),
                startedWallUnixNS: 1,
                model: "Mac16,13",
                osBuild: "24G419",
                appVersion: "0.1.0-test"
            ),
            configuration: configuration,
            definitions: [
                SeriesDefinition(
                    seriesID: SeriesID(Fixtures.uuid(101)),
                    metricID: try MetricID(validating: "fixture.cpu"),
                    definitionVersion: 1,
                    kind: .cpuZone,
                    displayName: "测试来源",
                    memberSourceIDs: [SourceID(Fixtures.uuid(1))],
                    formula: .identity
                )
            ],
            cpuPeriodMS: configuration.cpuDefaultMS
        )
        let gapID = GapID(Fixtures.uuid(720))
        let gap = Gap(
            gapID: gapID,
            seriesID: SeriesID(Fixtures.uuid(101)),
            startedElapsedNS: 1_000_000_000,
            endedElapsedNS: 2_000_000_000,
            reason: .readFailure
        )
        do {
            _ = try await engine.markGap(
                gap,
                lease: PersistenceLease(
                    reservationID: UUID(),
                    owner: .gap(gapID),
                    generation: 1,
                    maxRecords: 512,
                    maxBytes: 32 * 1024 * 1024
                )
            )
            Issue.record("expected receipt mismatch failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .databaseIntegrity)
        }

        let requestID = RequestID(Fixtures.uuid(721))
        let receipt = try await engine.accept(
            Fixtures.read(id: requestID, ms: 3000, values: [60]),
            lease: PersistenceLease(
                reservationID: UUID(),
                owner: .request(requestID),
                generation: 1,
                maxRecords: 512,
                maxBytes: 32 * 1024 * 1024
            )
        )
        let batch = try #require(await commit.committedBatch(for: receipt.batchID))
        #expect(batch.raw[0].segment == 1)
    }

    @Test func advanceEmitsTrendFromEMAHistory() async throws {
        let fixture = try await ProcessorFixture.make()
        // cpuZone 趋势窗口 5s、80% 覆盖 → 4s 跨度内至少 3 个 EMA 点
        for (index, ms) in [1000, 3000, 5000].enumerated() {
            let requestID = RequestID(Fixtures.uuid(730 + index))
            _ = try await fixture.accept(
                Fixtures.read(id: requestID, ms: Int64(ms), values: [20 + Double(index) * 0.04]),
                lease: fixture.lease(owner: .request(requestID), generation: 1)
            )
        }
        let receipt = try await fixture.advance(
            toMS: 5000,
            lease: fixture.lease(owner: .watermark(WatermarkEventID(Fixtures.uuid(733))), generation: 1)
        )
        let batch = try #require(await fixture.committedBatch(for: receipt))
        #expect(batch.trends.contains { $0.seriesID == fixture.seriesID && $0.direction == .stable })
    }
}

private func makeCalculator() throws -> TrendCalculator {
    TrendCalculator(configuration: try Configuration.bundledDefaults())
}

private func emaPoints(
    seriesID: SeriesID,
    segment: Int64,
    values: [(Int64, Double)]
) -> [EMAValue] {
    values.enumerated().map { index, entry in
        EMAValue(
            sampleID: "fixture-session:\(segment)-\(index)",
            seriesID: seriesID,
            segment: segment,
            timestamp: Fixtures.timestamp(ms: entry.0),
            valueC: entry.1
        )
    }
}

private extension GapReason {
    static var allCases: [GapReason] {
        [.readFailure, .sleep, .overload, .sourceChange, .clockChange, .timeout]
    }
}
