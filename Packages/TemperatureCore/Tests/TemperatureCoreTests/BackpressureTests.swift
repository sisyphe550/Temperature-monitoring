import Foundation
import Testing
@testable import TemperatureCore

@Suite struct BackpressureTests {
    @Test func wrongGenerationCommitIsIntegrityFailure() async throws {
        let fixture = try await PersistenceLeaseFixture.make()
        let owner = PersistenceOwner.request(RequestID(Fixtures.uuid(801)))
        let lease = try await fixture.session.reserve(
            owner: owner,
            generation: 1,
            maxRecords: 1,
            maxBytes: 1024
        )
        let batch = try fixture.emptyBatch()
        do {
            _ = try await fixture.session.commit(
                batch,
                using: PersistenceLease(
                    reservationID: lease.reservationID,
                    owner: owner,
                    generation: 2,
                    maxRecords: lease.maxRecords,
                    maxBytes: lease.maxBytes
                )
            )
            Issue.record("expected generation mismatch failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .databaseIntegrity)
            #expect(failure.underlyingCode == "owner_or_generation_mismatch")
        }
    }

    @Test func cancelledLeaseCannotCommit() async throws {
        let fixture = try await PersistenceLeaseFixture.make()
        let owner = PersistenceOwner.request(RequestID(Fixtures.uuid(802)))
        let lease = try await fixture.session.reserve(
            owner: owner,
            generation: 1,
            maxRecords: 1,
            maxBytes: 1024
        )
        await fixture.session.cancel(lease)
        do {
            _ = try await fixture.session.commit(try fixture.emptyBatch(), using: lease)
            Issue.record("expected cancelled lease failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .databaseIntegrity)
            #expect(failure.underlyingCode == "reservation_not_active")
        }
    }

    @Test func doubleCommitIsIntegrityFailure() async throws {
        let fixture = try await PersistenceLeaseFixture.make()
        let owner = PersistenceOwner.request(RequestID(Fixtures.uuid(803)))
        let lease = try await fixture.session.reserve(
            owner: owner,
            generation: 1,
            maxRecords: 1,
            maxBytes: 1024
        )
        let batch = try fixture.emptyBatch()
        _ = try await fixture.session.commit(batch, using: lease)
        do {
            _ = try await fixture.session.commit(try fixture.emptyBatch(), using: lease)
            Issue.record("expected double consume failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .databaseIntegrity)
            #expect(failure.underlyingCode == "reservation_not_active")
        }
    }

    @Test func forgedReservationIsIntegrityFailure() async throws {
        let fixture = try await PersistenceLeaseFixture.make()
        let owner = PersistenceOwner.request(RequestID(Fixtures.uuid(804)))
        let forged = PersistenceLease(
            reservationID: UUID(),
            owner: owner,
            generation: 1,
            maxRecords: 1,
            maxBytes: 1024
        )
        do {
            _ = try await fixture.session.commit(try fixture.emptyBatch(), using: forged)
            Issue.record("expected forged reservation failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .databaseIntegrity)
            #expect(failure.underlyingCode == "unknown_reservation")
        }
    }

    @Test func reserveAboveEventLimitIsIntegrityFailure() async throws {
        let fixture = try await PersistenceLeaseFixture.make()
        let owner = PersistenceOwner.request(RequestID(Fixtures.uuid(805)))
        do {
            _ = try await fixture.session.reserve(
                owner: owner,
                generation: 1,
                maxRecords: 513,
                maxBytes: 1024
            )
            Issue.record("expected reserve limit failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .databaseIntegrity)
            #expect(failure.underlyingCode == "reserve_exceeds_event_limit")
        }
    }

    @Test func highWatermarkPausesAndLowWatermarkResumes() async throws {
        let configuration = try makeWriterConfiguration(
            maxRecords: 8,
            pauseAt: 3,
            resumeBelow: 1
        )
        let fixture = try await PersistenceLeaseFixture.make(configuration: configuration)
        let owner = PersistenceOwner.request(RequestID(Fixtures.uuid(806)))

        var leases: [PersistenceLease] = []
        for generation in 1...3 {
            leases.append(
                try await fixture.session.reserve(
                    owner: owner,
                    generation: UInt64(generation),
                    maxRecords: 1,
                    maxBytes: 1024
                )
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
            Issue.record("expected backpressure reserve failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .databaseBackpressure)
        }

        for lease in leases {
            await fixture.session.cancel(lease)
        }
        #expect(await fixture.session.isBackpressureLatchedForTesting == false)

        _ = try await fixture.session.reserve(
            owner: owner,
            generation: 5,
            maxRecords: 1,
            maxBytes: 1024
        )
    }

    @Test func pausedWriterBlocksCommitUntilReleased() async throws {
        let fixture = try await PersistenceLeaseFixture.make()
        let owner = PersistenceOwner.request(RequestID(Fixtures.uuid(807)))
        let lease = try await fixture.session.reserve(
            owner: owner,
            generation: 1,
            maxRecords: 1,
            maxBytes: 1024
        )
        await fixture.session.setWriterPausedForTesting(true)
        do {
            _ = try await fixture.session.commit(try fixture.emptyBatch(), using: lease)
            Issue.record("expected paused writer failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .databaseBackpressure)
            #expect(failure.underlyingCode == "writer_paused")
        }

        await fixture.session.setWriterPausedForTesting(false)
        let retryLease = try await fixture.session.reserve(
            owner: owner,
            generation: 2,
            maxRecords: 1,
            maxBytes: 1024
        )
        let receipt = try await fixture.session.commit(try fixture.emptyBatch(), using: retryLease)
        #expect(receipt.acceptedRecords == 0)
    }

    @Test func engineCommitFailureDoesNotAdvanceSnapshotGeneration() async throws {
        let fixture = try await ProcessorFixture.make()
        let commit = TestCommitCapability(rejectNextReceipt: true)
        let configuration = try Configuration.bundledDefaults()
        let engine = MonitorEngine(
            clock: fixture.clock,
            commit: commit,
            session: SessionMetadata(
                sessionID: fixture.sessionID,
                startedWallUnixNS: 1_700_000_000_000_000_000,
                model: "Mac16,13",
                osBuild: "24G419",
                appVersion: "0.1.0-test"
            ),
            configuration: configuration,
            definitions: [
                SeriesDefinition(
                    seriesID: fixture.seriesID,
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
        let requestID = RequestID(Fixtures.uuid(810))
        let batch = Fixtures.read(id: requestID, ms: 100, values: [70])
        do {
            _ = try await engine.accept(
                batch,
                lease: fixture.lease(owner: .request(requestID), generation: 1)
            )
            Issue.record("expected receipt mismatch failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .databaseIntegrity)
        }
        let snapshot = await engine.snapshot(at: Fixtures.timestamp(ms: 100))
        #expect(snapshot.generation == 0)
        let raw = await engine.rawSamples(for: fixture.seriesID, nowElapsedNS: 100 * 1_000_000)
        #expect(raw.isEmpty)
    }

    @Test func commitPersistsExactlyOnce() async throws {
        let fixture = try await PersistenceLeaseFixture.make()
        let owner = PersistenceOwner.request(RequestID(Fixtures.uuid(808)))
        let lease = try await fixture.session.reserve(
            owner: owner,
            generation: 1,
            maxRecords: 512,
            maxBytes: 32 * 1024 * 1024
        )
        let batch = try Fixtures.persistence(id: BatchID(Fixtures.uuid(809)), value: 42.5, ms: 1000)
        let receipt = try await fixture.session.commit(batch, using: lease)
        #expect(receipt.acceptedRecords >= 2)
        #expect(try await fixture.session.rows(in: "raw_samples") == 1)
        #expect(try await fixture.session.rows(in: "ema_samples") == 1)
    }
}

private struct PersistenceLeaseFixture {
    let session: SessionPersistenceActor
    let databaseURL: URL

    static func make(configuration: RuntimeConfiguration? = nil) async throws -> PersistenceLeaseFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistenceLeaseFixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("session.sqlite")
        let runtimeConfiguration = try configuration ?? Configuration.bundledDefaults()
        let session = SessionPersistenceActor(databaseURL: databaseURL, configuration: runtimeConfiguration)
        try await session.open(
            SessionMetadata(
                sessionID: try SessionID(validating: "00000000-0000-4000-8000-000000000501"),
                startedWallUnixNS: 1_700_000_000_000_000_000,
                model: "Mac16,13",
                osBuild: "24G419",
                appVersion: "0.1.0-test"
            )
        )
        return PersistenceLeaseFixture(session: session, databaseURL: databaseURL)
    }

    func emptyBatch() throws -> PersistenceBatch {
        PersistenceBatch(
            batchID: BatchID(UUID()),
            sources: [],
            definitions: [],
            segments: [],
            raw: [],
            ema: [],
            buckets: [],
            trends: [],
            gaps: []
        )
    }

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
    let decoder = JSONDecoder()
    return try decoder.decode(RuntimeConfiguration.self, from: patched)
}
