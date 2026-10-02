import Foundation
import Testing
@testable import SensorRuntime
@testable import TemperatureCore

// Review-only regression tests in the temporary source copy.
// Assertions describe the required product behavior and are expected to fail
// against the reviewed implementation where that behavior is missing.
@Suite(.serialized) struct ProductAuditRegressionTests {
    @Test func completedReadReleasesPlannedWatermarkRegistration() async throws {
        let fixture = try await ProcessorFixture.make()
        let requestID = RequestID(Fixtures.uuid(9_101))
        await fixture.engine.registerInFlightReading(startElapsedNS: 200_000_000)

        let batch = ReadBatch(
            requestID: requestID,
            generation: 1,
            requestedPeriodMS: 200,
            readings: [
                Reading(
                    sourceID: SourceID(Fixtures.uuid(1)),
                    started: Fixtures.timestamp(ms: 201),
                    finished: Fixtures.timestamp(ms: 210),
                    outcome: .success(valueC: 70, sourceWallUnixNS: nil, freshness: .unknown)
                )
            ]
        )
        _ = try await fixture.accept(
            batch,
            lease: fixture.lease(owner: .request(requestID), generation: 1)
        )

        // Match ProcessingCoordinator's current registration/completion path:
        // the planned request start is registered, the observed start removed.
        await fixture.engine.unregisterInFlightReading(startElapsedNS: batch.readings[0].started.elapsedNS)
        let safeWatermark = await fixture.engine.safeWatermarkElapsedNS(at: Fixtures.timestamp(ms: 2_000))

        // A completed request must no longer block history window closure.
        #expect(safeWatermark == 2_000_000_000)
    }

    @Test func firstReadAfterWakeIsAcceptedWithUniqueRequestIdentity() async throws {
        let fixture = try await ControllerFixture.make()
        try await fixture.controller.start()
        fixture.clock.advance(to: Fixtures.timestamp(ms: 200))
        try await auditWaitUntil { await fixture.client.readCount == 1 }
        fixture.clock.advance(to: Fixtures.timestamp(ms: 210))
        await fixture.client.respond(allMembersCelsius: 70)
        try await auditWaitUntil { try await fixture.session.rows(in: "raw_samples") == 1 }
        let beforeSleepCount = try await fixture.session.rows(in: "raw_samples")

        try await fixture.controller.suspendForSleep()
        fixture.clock.advance(to: Fixtures.timestamp(ms: 5_000))
        try await fixture.controller.resumeAfterWake()
        fixture.clock.advance(to: Fixtures.timestamp(ms: 5_200))
        try await auditWaitUntil { await fixture.client.readCount == 2 }
        fixture.clock.advance(to: Fixtures.timestamp(ms: 5_300))
        await fixture.client.respond(allMembersCelsius: 80)
        try await auditWaitUntil {
            if await fixture.controller.lastAcceptFailure() != nil {
                return true
            }
            return try await fixture.session.rows(in: "raw_samples") > beforeSleepCount
        }

        let wakeFailure = await fixture.controller.lastAcceptFailure()
        let afterWakeCount = try await fixture.session.rows(in: "raw_samples")
        #expect(wakeFailure == nil)
        #expect(afterWakeCount == beforeSleepCount + 1)

        await fixture.controller.stop()
        try await fixture.closeAndDeleteSession()
    }

    @Test func historyRequestWithFreshSystemClockRetainsCurrentSessionSample() async throws {
        let fixture = try await ProcessorFixture.make()
        let sessionClock = SystemClock()
        try await Task.sleep(nanoseconds: 40_000_000)
        let observedAt = sessionClock.now()
        let requestID = RequestID(Fixtures.uuid(9_102))
        let batch = ReadBatch(
            requestID: requestID,
            generation: 1,
            requestedPeriodMS: 200,
            readings: [
                Reading(
                    sourceID: SourceID(Fixtures.uuid(1)),
                    started: observedAt,
                    finished: observedAt,
                    outcome: .success(valueC: 70, sourceWallUnixNS: nil, freshness: .unknown)
                )
            ]
        )
        _ = try await fixture.accept(
            batch,
            lease: fixture.lease(owner: .request(requestID), generation: 1)
        )
        let sessionHistory = await fixture.engine.realtime(
            HistoryRequest(
                seriesIDs: [fixture.seriesID],
                range: .fiveMinutes,
                asOfElapsedNS: sessionClock.now().elapsedNS,
                pointLimit: 2_000
            )
        )
        #expect(sessionHistory.points.count == 1)

        // Reproduce the App request construction with a new default clock.
        // Its elapsed origin must not exclude the session's current sample.
        let queryClock = SystemClock()
        let queryAsOf = queryClock.now().elapsedNS
        let newClockHistory = await fixture.engine.realtime(
            HistoryRequest(
                seriesIDs: [fixture.seriesID],
                range: .fiveMinutes,
                asOfElapsedNS: queryAsOf,
                pointLimit: 2_000
            )
        )

        #expect(newClockHistory.points == sessionHistory.points)
        #expect(newClockHistory.points.count == 1)
    }

    @Test func normalRuntimeTickPrunesExpiredPersistedSamples() async throws {
        let fixture = try await ControllerFixture.make()
        try await fixture.controller.start()
        fixture.clock.advance(to: Fixtures.timestamp(ms: 200))
        try await auditWaitUntil { await fixture.client.readCount == 1 }
        fixture.clock.advance(to: Fixtures.timestamp(ms: 210))
        await fixture.client.respond(allMembersCelsius: 70)
        try await auditWaitUntil { try await fixture.session.rows(in: "raw_samples") == 1 }

        // Supply the already-persisted parent required by the Raw deletion rule,
        // isolating the missing periodic cleanup from the watermark defect.
        _ = try await fixture.session.appendForTesting(
            PersistenceBatch(
                batchID: BatchID(Fixtures.uuid(9_103)),
                sources: [],
                definitions: [],
                segments: [],
                raw: [],
                ema: [],
                buckets: [
                    Bucket(
                        seriesID: fixture.seriesID,
                        segment: 1,
                        widthSeconds: 1,
                        startElapsedNS: 0,
                        endElapsedNS: 1_000_000_000,
                        minC: 70,
                        maxC: 70,
                        sumC: 70,
                        count: 1,
                        latestC: 70,
                        latestElapsedNS: 210_000_000,
                        latestSampleID: "audit-parent-evidence",
                        isPartial: true,
                        coverageNS: 200_000_000
                    )
                ],
                trends: [],
                gaps: []
            )
        )
        let configuration = try Configuration.bundledDefaults()
        let afterCleanupDeadlineSeconds = configuration.retentionSeconds.raw
            + configuration.retentionGraceSeconds
            + configuration.retentionTickSeconds + 1
        fixture.clock.advance(to: Fixtures.timestamp(ms: afterCleanupDeadlineSeconds * 1_000))
        try await Task.sleep(nanoseconds: 100_000_000)

        let rawCount = try await fixture.session.rows(in: "raw_samples")
        let emaCount = try await fixture.session.rows(in: "ema_samples")
        #expect(rawCount == 0)
        #expect(emaCount == 0)

        await fixture.controller.stop()
        try await fixture.closeAndDeleteSession()
    }
}

private enum ProductAuditFixtureError: Error {
    case conditionTimedOut
}

private func auditWaitUntil(
    _ predicate: () async throws -> Bool
) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if try await predicate() {
            return
        }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
    throw ProductAuditFixtureError.conditionTimedOut
}
