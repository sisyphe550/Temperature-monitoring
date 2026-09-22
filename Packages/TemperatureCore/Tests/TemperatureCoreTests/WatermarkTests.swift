import Foundation
import Testing
@testable import TemperatureCore

@Suite struct WatermarkTests {
    @Test func inFlightReadingBlocksOneSecondClosure() async throws {
        let fixture = try await ProcessorFixture.make()
        await fixture.engine.registerInFlightReading(startElapsedNS: 950_000_000)

        let watermarkID = WatermarkEventID(Fixtures.uuid(901))
        do {
            _ = try await fixture.advance(
                toMS: 1000,
                lease: fixture.lease(owner: .watermark(watermarkID), generation: 1)
            )
            Issue.record("expected unsafe watermark")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .processingValidate)
            #expect(failure.underlyingCode == "unsafe_watermark")
        }

        await fixture.engine.unregisterInFlightReading(startElapsedNS: 950_000_000)
        let receipt = try await fixture.advance(
            toMS: 1000,
            lease: fixture.lease(owner: .watermark(WatermarkEventID(Fixtures.uuid(902))), generation: 1)
        )
        let batch = try #require(await fixture.committedBatch(for: receipt))
        #expect(batch.buckets.isEmpty)
        #expect(batch.trends.count == 1)
    }

    @Test func lateSampleLandsInSecondBucketAfterSafeAdvance() async throws {
        let fixture = try await ProcessorFixture.make()
        let requestID = RequestID(Fixtures.uuid(903))
        let start = Fixtures.timestamp(ms: 950)
        let finish = Fixtures.timestamp(ms: 1050)

        await fixture.engine.registerInFlightReading(startElapsedNS: start.elapsedNS)
        let batch = ReadBatch(
            requestID: requestID,
            generation: 1,
            readings: [
                Reading(
                    sourceID: SourceID(Fixtures.uuid(1)),
                    started: start,
                    finished: finish,
                    outcome: .success(valueC: 95, sourceWallUnixNS: nil, freshness: .unknown)
                )
            ]
        )
        _ = try await fixture.accept(
            batch,
            lease: fixture.lease(owner: .request(requestID), generation: 1)
        )
        await fixture.engine.unregisterInFlightReading(startElapsedNS: start.elapsedNS)

        let advanceLease = fixture.lease(
            owner: .watermark(WatermarkEventID(Fixtures.uuid(904))),
            generation: 1
        )
        let receipt = try await fixture.advance(toMS: 2000, lease: advanceLease)
        let persisted = try #require(await fixture.committedBatch(for: receipt))
        #expect(persisted.buckets.count == 1)
        #expect(persisted.buckets[0].startElapsedNS == 1_000_000_000)
        #expect(persisted.buckets[0].latestC == 95)
    }

    @Test func staleGenerationIsRejectedWithoutStateChange() async throws {
        let fixture = try await ProcessorFixture.make()
        let acceptedID = RequestID(Fixtures.uuid(905))
        _ = try await fixture.accept(
            Fixtures.read(id: acceptedID, ms: 100, values: [80]),
            lease: fixture.lease(owner: .request(acceptedID), generation: 1)
        )

        let staleID = RequestID(Fixtures.uuid(906))
        let stale = ReadBatch(
            requestID: staleID,
            generation: 0,
            readings: [
                Reading(
                    sourceID: SourceID(Fixtures.uuid(1)),
                    started: Fixtures.timestamp(ms: 120),
                    finished: Fixtures.timestamp(ms: 140),
                    outcome: .success(valueC: 90, sourceWallUnixNS: nil, freshness: .unknown)
                )
            ]
        )
        do {
            _ = try await fixture.accept(
                stale,
                lease: fixture.lease(owner: .request(staleID), generation: 0)
            )
            Issue.record("expected stale generation failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .processingValidate)
            #expect(failure.underlyingCode == "stale_generation")
        }

        let raw = await fixture.rawSamples(nowMS: 140)
        #expect(raw.count == 1)
        #expect(raw[0].valueC == 80)
    }

    @Test func receiptMismatchDoesNotAdvanceSnapshotGeneration() async throws {
        let commit = TestCommitCapability(rejectNextReceipt: true)
        let configuration = try Configuration.bundledDefaults()
        let engine = MonitorEngine(
            clock: TestClock(now: Fixtures.timestamp(ms: 0)),
            commit: commit,
            session: SessionMetadata(
                sessionID: try SessionID(validating: "00000000-0000-4000-8000-000000000403"),
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
        let requestID = RequestID(Fixtures.uuid(906))
        let batch = Fixtures.read(id: requestID, ms: 100, values: [70])
        do {
            _ = try await engine.accept(
                batch,
                lease: PersistenceLease(
                    reservationID: UUID(),
                    owner: .request(requestID),
                    generation: 1,
                    maxRecords: 512,
                    maxBytes: 32 * 1024 * 1024
                )
            )
            Issue.record("expected receipt mismatch failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .databaseIntegrity)
        }

        let snapshot = await engine.snapshot(at: Fixtures.timestamp(ms: 100))
        #expect(snapshot.generation == 0)
    }

    @Test func safeWatermarkCapsAtBlockedWindowEnd() {
        let safe = SafeWatermark.maximumClosureElapsedNS(
            nowElapsedNS: 2_000_000_000,
            inFlightStartElapsedNS: [950_000_000]
        )
        #expect(safe == 999_999_999)
    }
}
