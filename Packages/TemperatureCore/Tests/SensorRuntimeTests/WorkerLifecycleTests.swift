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
}
