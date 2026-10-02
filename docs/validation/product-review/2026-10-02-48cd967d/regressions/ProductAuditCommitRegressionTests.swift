import Foundation
import Testing
@testable import TemperatureCore

@Suite struct ProductAuditCommitRegressionTests {
    @Test func failedPersistenceDoesNotAdvanceStateBeforeRetry() async throws {
        let clock = TestClock(now: Fixtures.timestamp(ms: 0))
        let commit = AuditFailFirstCommit()
        let sourceID = SourceID(Fixtures.uuid(1))
        let seriesID = SeriesID(Fixtures.uuid(101))
        let metadata = SessionMetadata(sessionID: SessionID(UUID()), startedWallUnixNS: 1,
            model: "Mac16,13", osBuild: "24G419", appVersion: "audit")
        let definition = SeriesDefinition(seriesID: seriesID,
            metricID: try MetricID(validating: "audit.cpu"), definitionVersion: 1,
            kind: .cpuZone, displayName: "audit", memberSourceIDs: [sourceID], formula: .identity)
        let engine = MonitorEngine(clock: clock, commit: commit, session: metadata,
            configuration: try Configuration.bundledDefaults(), definitions: [definition], cpuPeriodMS: 200)
        let requestID = RequestID(UUID())
        let lease = PersistenceLease(reservationID: UUID(), owner: .request(requestID), generation: 1,
            maxRecords: 512, maxBytes: 33_554_432)
        let batch = ReadBatch(requestID: requestID, generation: 1, requestedPeriodMS: 200,
            readings: [Reading(sourceID: sourceID, started: Fixtures.timestamp(ms: 190),
                finished: Fixtures.timestamp(ms: 200),
                outcome: .success(valueC: 70, sourceWallUnixNS: nil, freshness: .unknown))])
        var firstAttemptFailed = false
        do { _ = try await engine.accept(batch, lease: lease) } catch { firstAttemptFailed = true }
        #expect(firstAttemptFailed)
        var retryWasAccepted = false
        do { _ = try await engine.accept(batch, lease: lease); retryWasAccepted = true }
        catch { Issue.record("same-batch retry failed after uncommitted write: \(error)") }
        #expect(retryWasAccepted)
        let persisted = await commit.successCount
        #expect(persisted == 1)
    }
}

private enum AuditCommitError: Error { case temporaryWriteFailure }
private actor AuditFailFirstCommit: PersistenceCommitCapability {
    private var attempts = 0
    private(set) var successCount = 0
    func commit(_ batch: PersistenceBatch, using lease: PersistenceLease) async throws -> ProcessingReceipt {
        attempts += 1
        if attempts == 1 { throw AuditCommitError.temporaryWriteFailure }
        successCount += 1
        return ProcessingReceipt(batchID: batch.batchID,
            acceptedRecords: PersistenceBatchMetrics.logicalRecordCount(batch), snapshotGeneration: 1)
    }
}
