import Foundation
import Testing
@testable import TemperatureCore

@Suite struct ProcessingIdentityTests {
    @Test func failureReadingProducesNoSample() async throws {
        let fixture = try await ProcessorFixture.make()
        let requestID = RequestID(Fixtures.uuid(301))
        let lease = fixture.lease(owner: .request(requestID), generation: 1)
        let batch = ReadBatch(
            requestID: requestID,
            generation: 1,
            readings: [
                Reading(
                    sourceID: SourceID(Fixtures.uuid(1)),
                    started: Fixtures.timestamp(ms: 0),
                    finished: Fixtures.timestamp(ms: 0),
                    outcome: .failure(
                        MonitorFailure(
                            code: .sensorRead,
                            severity: .capability,
                            component: "SensorClient",
                            operation: "read",
                            retryCount: 0,
                            sourceID: SourceID(Fixtures.uuid(1)),
                            underlyingCode: "fixture"
                        )
                    )
                )
            ]
        )

        let receipt = try await fixture.accept(batch, lease: lease)
        let committed = try #require(await fixture.committedBatch(for: receipt))
        #expect(committed.raw.isEmpty)
        #expect(await fixture.rawSamples(nowMS: 0).isEmpty)
    }

    @Test func rejectsNonFiniteAndBelowAbsoluteZero() async throws {
        let fixture = try await ProcessorFixture.make()
        let invalidValues: [Double] = [.nan, .infinity, -.infinity, -274]

        for (index, value) in invalidValues.enumerated() {
            let requestID = RequestID(Fixtures.uuid(310 + index))
            let lease = fixture.lease(owner: .request(requestID), generation: 1)
            let batch = ReadBatch(
                requestID: requestID,
                generation: 1,
                readings: [
                    Reading(
                        sourceID: SourceID(Fixtures.uuid(1)),
                        started: Fixtures.timestamp(ms: Int64(index * 10)),
                        finished: Fixtures.timestamp(ms: Int64(index * 10)),
                        outcome: .success(valueC: value, sourceWallUnixNS: nil, freshness: .unknown)
                    )
                ]
            )

            do {
                _ = try await fixture.accept(batch, lease: lease)
                Issue.record("expected validation failure for \(value)")
            } catch let failure as MonitorFailure {
                #expect(failure.code == .processingValidate)
            }
        }
    }

    @Test func duplicateTemperatureValuesKeepSeparateSamples() async throws {
        let fixture = try await ProcessorFixture.make()
        let firstID = RequestID(Fixtures.uuid(320))
        let secondID = RequestID(Fixtures.uuid(321))
        let firstLease = fixture.lease(owner: .request(firstID), generation: 1)
        let secondLease = fixture.lease(owner: .request(secondID), generation: 1)

        _ = try await fixture.accept(
            Fixtures.read(id: firstID, ms: 0, values: [70]),
            lease: firstLease
        )
        _ = try await fixture.accept(
            Fixtures.read(id: secondID, ms: 50, values: [70]),
            lease: secondLease
        )

        let samples = await fixture.rawSamples(nowMS: 50)
        #expect(samples.count == 2)
        #expect(samples[0].valueC == 70)
        #expect(samples[1].valueC == 70)
        #expect(samples[0].sampleID != samples[1].sampleID)
    }

    @Test func repeatedRequestIsIdempotent() async throws {
        let fixture = try await ProcessorFixture.make()
        let requestID = RequestID(Fixtures.uuid(330))
        let lease = fixture.lease(owner: .request(requestID), generation: 1)
        let batch = Fixtures.read(id: requestID, ms: 0, values: [72])

        let first = try await fixture.accept(batch, lease: lease)
        let second = try await fixture.accept(batch, lease: lease)

        #expect(first == second)
        #expect(await fixture.commit.committed.count == 1)
        #expect(await fixture.rawSamples(nowMS: 0).count == 1)
    }

    @Test func sameRequestIDDifferentPayloadFails() async throws {
        let fixture = try await ProcessorFixture.make()
        let requestID = RequestID(Fixtures.uuid(331))
        let lease = fixture.lease(owner: .request(requestID), generation: 1)

        _ = try await fixture.accept(
            Fixtures.read(id: requestID, ms: 0, values: [72]),
            lease: lease
        )

        let altered = ReadBatch(
            requestID: requestID,
            generation: 1,
            readings: [
                Reading(
                    sourceID: SourceID(Fixtures.uuid(1)),
                    started: Fixtures.timestamp(ms: 0),
                    finished: Fixtures.timestamp(ms: 0),
                    outcome: .success(valueC: 73, sourceWallUnixNS: nil, freshness: .unknown)
                )
            ]
        )

        do {
            _ = try await fixture.accept(altered, lease: lease)
            Issue.record("expected request mismatch failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .databaseIntegrity)
            #expect(failure.underlyingCode == "request_content_mismatch")
        }
    }

    @Test func staleGenerationIsRejected() async throws {
        let fixture = try await ProcessorFixture.make()
        let requestID = RequestID(Fixtures.uuid(332))

        _ = try await fixture.accept(
            ReadBatch(
                requestID: RequestID(Fixtures.uuid(333)),
                generation: 2,
                readings: Fixtures.read(id: RequestID(Fixtures.uuid(333)), ms: 0, values: [70]).readings
            ),
            lease: fixture.lease(owner: .request(RequestID(Fixtures.uuid(333))), generation: 2)
        )

        do {
            _ = try await fixture.accept(
                ReadBatch(
                    requestID: requestID,
                    generation: 1,
                    readings: Fixtures.read(id: requestID, ms: 50, values: [71]).readings
                ),
                lease: fixture.lease(owner: .request(requestID), generation: 1)
            )
            Issue.record("expected stale generation rejection")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .processingValidate)
            #expect(failure.underlyingCode == "stale_generation")
        }
    }

    @Test func upstreamRollbackDoesNotCreateSample() async throws {
        let fixture = try await ProcessorFixture.make()
        let firstID = RequestID(Fixtures.uuid(340))
        let secondID = RequestID(Fixtures.uuid(341))

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

    @Test func nonMonotonicElapsedIsRejected() async throws {
        let fixture = try await ProcessorFixture.make()
        let firstID = RequestID(Fixtures.uuid(350))
        let secondID = RequestID(Fixtures.uuid(351))

        _ = try await fixture.accept(
            Fixtures.read(id: firstID, ms: 100, values: [80]),
            lease: fixture.lease(owner: .request(firstID), generation: 1)
        )

        do {
            _ = try await fixture.accept(
                Fixtures.read(id: secondID, ms: 100, values: [81]),
                lease: fixture.lease(owner: .request(secondID), generation: 1)
            )
            Issue.record("expected non-monotonic rejection")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .processingValidate)
            #expect(failure.underlyingCode == "non_monotonic_elapsed")
        }
    }

    @Test func thirtyThirdSeriesIsRejected() async throws {
        let configuration = try Configuration.bundledDefaults()
        let clock = TestClock(now: Fixtures.timestamp(ms: 0))
        let commit = TestCommitCapability()
        let sessionID = try SessionID(validating: "00000000-0000-4000-8000-000000000402")
        var definitions: [SeriesDefinition] = []
        for index in 0..<32 {
            let sourceID = SourceID(Fixtures.uuid(500 + index))
            definitions.append(
                SeriesDefinition(
                    seriesID: SeriesID(Fixtures.uuid(600 + index)),
                    metricID: try MetricID(validating: "fixture.cpu.\(index)"),
                    definitionVersion: 1,
                    kind: .cpuZone,
                    displayName: "来源 \(index)",
                    memberSourceIDs: [sourceID],
                    formula: .identity
                )
            )
        }
        let engine = MonitorEngine(
            clock: clock,
            commit: commit,
            session: SessionMetadata(
                sessionID: sessionID,
                startedWallUnixNS: 1,
                model: "Mac16,13",
                osBuild: "24G419",
                appVersion: "0.1.0-test"
            ),
            configuration: configuration,
            definitions: definitions,
            cpuPeriodMS: configuration.cpuDefaultMS
        )

        let extraSource = SourceID(Fixtures.uuid(999))
        let requestID = RequestID(Fixtures.uuid(998))
        let batch = ReadBatch(
            requestID: requestID,
            generation: 1,
            readings: [
                Reading(
                    sourceID: extraSource,
                    started: Fixtures.timestamp(ms: 0),
                    finished: Fixtures.timestamp(ms: 0),
                    outcome: .success(valueC: 70, sourceWallUnixNS: nil, freshness: .unknown)
                )
            ]
        )

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
            Issue.record("expected unknown source for extra series")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .processingValidate)
            #expect(failure.underlyingCode == "unknown_source")
        }
    }
}
