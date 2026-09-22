import Foundation
import Testing
@testable import SensorRuntime
import TemperatureCore

@Suite(.serialized) struct WorkerLifecycleTests {
    private func requestID(_ ordinal: Int) throws -> RequestID {
        try RequestID(validating: String(format: "00000000-0000-4000-8000-%012d", ordinal))
    }

    @Test func successDiscoverReturnsCatalog() async throws {
        let client = try WorkerTestSupport.client(scenario: "success")
        let catalog = try await client.discoverRaw()
        let connectionGeneration = await client.connectionGeneration
        #expect(catalog.generation == connectionGeneration)
        #expect(catalog.sources.count == 1)
        #expect(catalog.sources[0].transportHandle == "smc:Tp01")
        await client.close()
    }

    @Test func rejectsOversizeResponse() async throws {
        let client = try WorkerTestSupport.client(scenario: "oversize")
        do {
            _ = try await client.discoverRaw()
            Issue.record("expected protocol failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .sensorProtocol)
        }
        await client.close()
    }

    @Test func rejectsBadJSONResponse() async throws {
        let client = try WorkerTestSupport.client(scenario: "badJSON")
        do {
            _ = try await client.discoverRaw()
            Issue.record("expected protocol failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .sensorProtocol)
        }
        await client.close()
    }

    @Test func rejectsWrongResponseID() async throws {
        let client = try WorkerTestSupport.client(scenario: "wrongID")
        do {
            _ = try await client.discoverRaw()
            Issue.record("expected protocol failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .sensorProtocol)
        }
        await client.close()
    }

    @Test func rejectsOldGenerationResponse() async throws {
        let client = try WorkerTestSupport.client(scenario: "oldGeneration")
        do {
            _ = try await client.discoverRaw()
            Issue.record("expected protocol failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .sensorProtocol)
        }
        await client.close()
    }

    @Test func mapsCrashToProtocolFailure() async throws {
        let client = try WorkerTestSupport.client(scenario: "crash")
        do {
            _ = try await client.discoverRaw()
            Issue.record("expected protocol failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .sensorProtocol)
        }
        await client.close()
    }

    @Test func closeIsIdempotent() async throws {
        let client = try WorkerTestSupport.client(scenario: "success")
        _ = try await client.discoverRaw()
        await client.close()
        await client.close()
    }

    @Test func respawnsAfterCrashWithNewGeneration() async throws {
        let client = try WorkerTestSupport.client(scenario: "crash")
        do {
            _ = try await client.discoverRaw()
            Issue.record("expected protocol failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .sensorProtocol)
        }

        let recovered = try WorkerTestSupport.client(scenario: "success")
        let catalog = try await recovered.discoverRaw()
        #expect(catalog.generation == 1)
        await recovered.close()
        await client.close()
    }

    @Test func discoveredSourcesExposeHandlesNotSourceIDs() async throws {
        let client = try WorkerTestSupport.client(scenario: "success")
        let catalog = try await client.discoverRaw()
        let source = catalog.sources[0]
        #expect(source.transportHandle == "smc:Tp01")
        #expect(source.rawKey == "Tp01")
        let transportRequest = TransportReadRequest(
            requestID: try requestID(301),
            generation: catalog.generation,
            transportHandles: catalog.sources.map { $0.transportHandle },
            requestedPeriodMS: 200
        )
        #expect(transportRequest.transportHandles == ["smc:Tp01"])
        await client.close()
    }

    @Test func successDiscoverAndReadOnSameConnection() async throws {
        let client = try WorkerTestSupport.client(scenario: "success")
        let catalog = try await client.discoverRaw()
        let batch = try await client.readRaw(
            TransportReadRequest(
                requestID: try requestID(201),
                generation: catalog.generation,
                transportHandles: catalog.sources.map(\.transportHandle),
                requestedPeriodMS: 200
            )
        )
        #expect(batch.readings.count == 1)
        if case .success(let valueC, _, _) = batch.readings[0].outcome {
            #expect(valueC == 25.5)
        } else {
            Issue.record("expected successful reading outcome")
        }
        await client.close()
    }

    @Test func discoverTimeoutRecyclesWorker() async throws {
        let client = try WorkerTestSupport.client(
            scenario: "hangDiscover",
            timeouts: WorkerTestSupport.fastTimeouts
        )
        do {
            _ = try await client.discoverRaw()
            Issue.record("expected discover timeout")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .sensorTimeout)
        }
        let replacement = try WorkerTestSupport.client(scenario: "success", timeouts: WorkerTestSupport.fastTimeouts)
        _ = try await replacement.discoverRaw()
        await client.close()
        await replacement.close()
    }

    @Test func readTimeoutRecyclesWorker() async throws {
        let client = try WorkerTestSupport.client(
            scenario: "hangRead",
            timeouts: WorkerTestSupport.fastTimeouts
        )
        let catalog = try await client.discoverRaw()
        do {
            _ = try await client.readRaw(
                TransportReadRequest(
                    requestID: try requestID(401),
                    generation: catalog.generation,
                    transportHandles: catalog.sources.map(\.transportHandle),
                    requestedPeriodMS: 200
                )
            )
            Issue.record("expected read timeout")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .sensorTimeout)
        }
        await client.close()
    }

    @Test func ignoreTermEndsWithKillWithinGrace() async throws {
        let client = try WorkerTestSupport.client(
            scenario: "ignoreTerm",
            timeouts: WorkerTestSupport.fastTimeouts
        )
        do {
            _ = try await client.discoverRaw()
            Issue.record("expected timeout for ignoreTerm worker")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .sensorTimeout)
        }
        let replacement = try WorkerTestSupport.client(scenario: "success", timeouts: WorkerTestSupport.fastTimeouts)
        _ = try await replacement.discoverRaw()
        await client.close()
        await replacement.close()
    }

    @Test func lateReplyDoesNotSatisfyTimedOutRequest() async throws {
        let client = try WorkerTestSupport.client(
            scenario: "lateRead",
            timeouts: WorkerTestSupport.fastTimeouts
        )
        let catalog = try await client.discoverRaw()
        do {
            _ = try await client.readRaw(
                TransportReadRequest(
                    requestID: try requestID(701),
                    generation: catalog.generation,
                    transportHandles: catalog.sources.map(\.transportHandle),
                    requestedPeriodMS: 200
                )
            )
            Issue.record("expected lateRead timeout")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .sensorTimeout)
        }
        await client.close()
    }

    @Test func qualifiedClientClearsCatalogAfterReadTimeout() async throws {
        let profile = try Configuration.bundledProfile()
        let worker = try WorkerTestSupport.client(
            scenario: "hangRead",
            timeouts: WorkerTestSupport.fastTimeouts
        )
        let client = QualifiedSensorClient(
            transport: worker,
            registry: ProfileRegistry(profile: profile)
        )
        let qualified = try await client.discover()
        guard let source = qualified.available.first else {
            Issue.record("expected qualified source")
            return
        }
        do {
            _ = try await client.read(
                ReadRequest(
                    requestID: try requestID(501),
                    sourceIDs: [source.sourceID],
                    requestedPeriodMS: 200
                )
            )
            Issue.record("expected read timeout")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .sensorTimeout)
        }
        #expect(await client.qualifiedCatalog == nil)
        await client.close()
    }

    @Test func staleQualifiedCatalogDoesNotProduceReadBatch() async throws {
        let profile = try Configuration.bundledProfile()
        let catalog = try WorkerLifecycleQualifyFixture.fullCPUCatalog(for: profile)
        let transport = WorkerLifecycleQualifyFixture.GenerationalStubTransport(catalog: catalog)
        let client = QualifiedSensorClient(
            transport: transport,
            registry: ProfileRegistry(profile: profile)
        )
        let qualified = try await client.discover()
        let source = try #require(qualified.available.first)
        transport.liveGeneration = 2
        do {
            _ = try await client.read(
                ReadRequest(
                    requestID: try requestID(601),
                    sourceIDs: [source.sourceID],
                    requestedPeriodMS: 200
                )
            )
            Issue.record("expected generation mismatch")
        } catch QualifiedSensorClientError.generationMismatch {
            #expect(await client.qualifiedCatalog == nil)
        }
        await client.close()
    }

    @Test func consecutiveCloseAfterTimeoutIsIdempotent() async throws {
        let client = try WorkerTestSupport.client(
            scenario: "hangDiscover",
            timeouts: WorkerTestSupport.fastTimeouts
        )
        do {
            _ = try await client.discoverRaw()
            Issue.record("expected discover timeout")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .sensorTimeout)
        }
        await client.close()
        await client.close()
    }
}

private enum WorkerLifecycleQualifyFixture {
    final class GenerationalStubTransport: SensorTransport, SensorConnectionGeneration, @unchecked Sendable {
        let catalog: DiscoveredCatalog
        var liveGeneration: UInt64

        init(catalog: DiscoveredCatalog) {
            self.catalog = catalog
            self.liveGeneration = catalog.generation
        }

        func currentConnectionGeneration() async -> UInt64 {
            liveGeneration
        }

        func discoverRaw() async throws -> DiscoveredCatalog {
            catalog
        }

        func readRaw(_ request: TransportReadRequest) async throws -> TransportReadBatch {
            TransportReadBatch(
                requestID: request.requestID,
                generation: request.generation,
                readings: request.transportHandles.map { handle in
                    TransportReading(
                        transportHandle: handle,
                        started: Timestamp(elapsedNS: 0, wallUnixNS: 1),
                        finished: Timestamp(elapsedNS: 1_000_000, wallUnixNS: 2),
                        outcome: .success(valueC: 25.5, sourceWallUnixNS: nil, freshness: .unknown)
                    )
                }
            )
        }

        func close() async {}
    }

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
