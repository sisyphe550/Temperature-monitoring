import Foundation
import Testing
import SensorRuntime
import TemperatureCore

@Suite struct DiscoveryFactsProtocolTests {
    @Test func roundTripsRealNVMeInterconnectFacts() throws {
        let source = DiscoveredSource(
            transportHandle: "nvme:42", provider: .nvme, rawKey: "TEMPERATURE",
            registryID: "42", encoding: "uint16_le_kelvin", byteCount: 2,
            physicalInterconnectLocation: "Internal", interconnectLookupStatus: .found
        )
        let request = try discoverRequest()
        let response = WorkerProtocol.Response(
            requestID: request.requestID, generation: request.generation, command: .discover,
            payload: .catalog(DiscoveredCatalog(generation: request.generation, sources: [source]))
        )
        let data = try WorkerProtocol.encodeResponse(response)
        let decoded = try WorkerProtocol.decodeResponse(from: data, matching: request)
        #expect(decoded == response)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"physicalInterconnectLocation\":\"Internal\""))
        #expect(text.contains("\"interconnectLookupStatus\":\"found\""))
    }

    @Test func unattemptedProviderFactsRemainNilAndAreOmitted() throws {
        let request = try discoverRequest()
        let source = DiscoveredSource(
            transportHandle: "smc:TB1T", provider: .smc, rawKey: "TB1T",
            registryID: "TB1T", encoding: "flt ", byteCount: 4
        )
        let response = WorkerProtocol.Response(
            requestID: request.requestID, generation: request.generation, command: .discover,
            payload: .catalog(DiscoveredCatalog(generation: request.generation, sources: [source]))
        )
        let data = try WorkerProtocol.encodeResponse(response)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("physicalInterconnectLocation"))
        #expect(!text.contains("interconnectLookupStatus"))
        #expect(try WorkerProtocol.decodeResponse(from: data, matching: request) == response)
    }

    @Test func rejectsUnknownAndNonstringLookupStates() throws {
        let invalidStatuses: [Any] = ["ok", "unknown", 1, true, NSNull()]
        for invalid in invalidStatuses {
            let data = try responseData(fields: ["interconnectLookupStatus": invalid])
            #expect(throws: WorkerProtocolError.invalidResponsePayload) {
                _ = try WorkerProtocol.decodeResponse(from: data, matching: discoverRequest())
            }
        }
    }

    @Test func rejectsFoundWithoutValidLocation() throws {
        let missing = try responseData(fields: ["interconnectLookupStatus": "found"])
        #expect(throws: WorkerProtocolError.invalidResponsePayload) {
            _ = try WorkerProtocol.decodeResponse(from: missing, matching: discoverRequest())
        }
        let invalidLocations: [Any] = ["", "  ", "Internal\0External", 42, true, NSNull()]
        for invalid in invalidLocations {
            let data = try responseData(fields: [
                "interconnectLookupStatus": "found", "physicalInterconnectLocation": invalid,
            ])
            #expect(throws: WorkerProtocolError.invalidResponsePayload) {
                _ = try WorkerProtocol.decodeResponse(from: data, matching: discoverRequest())
            }
        }
    }

    @Test func encoderRejectsFoundWithoutLocation() throws {
        let request = try discoverRequest()
        let source = DiscoveredSource(
            transportHandle: "nvme:42", provider: .nvme, rawKey: "TEMPERATURE",
            registryID: "42", encoding: "uint16_le_kelvin", byteCount: 2,
            interconnectLookupStatus: .found
        )
        let response = WorkerProtocol.Response(
            requestID: request.requestID, generation: request.generation, command: .discover,
            payload: .catalog(DiscoveredCatalog(generation: request.generation, sources: [source]))
        )
        #expect(throws: WorkerProtocolError.invalidResponsePayload) {
            _ = try WorkerProtocol.encodeResponse(response)
        }
    }

    @Test func missingAndFailedLookupsRoundTripWithoutLocation() throws {
        for status in [InterconnectLookupStatus.missingProperty, .lookupFailed] {
            let data = try responseData(fields: ["interconnectLookupStatus": status.rawValue])
            let response = try WorkerProtocol.decodeResponse(from: data, matching: discoverRequest())
            guard case .catalog(let catalog) = response.payload else {
                Issue.record("expected discovered catalog")
                continue
            }
            let source = try #require(catalog.sources.first)
            #expect(source.interconnectLookupStatus == status)
            #expect(source.physicalInterconnectLocation == nil)
        }
    }

    private func discoverRequest() throws -> WorkerProtocol.Request {
        WorkerProtocol.Request(
            requestID: try RequestID(validating: "00000000-0000-4000-8000-000000000701"),
            generation: 1, command: .discover
        )
    }

    private func responseData(fields: [String: Any]) throws -> Data {
        var source: [String: Any] = [
            "transportHandle": "nvme:42", "provider": "nvme", "rawKey": "TEMPERATURE",
            "registryID": "42", "encoding": "uint16_le_kelvin", "byteCount": 2,
        ]
        source.merge(fields) { _, replacement in replacement }
        return try JSONSerialization.data(withJSONObject: [
            "version": 1, "requestID": try discoverRequest().requestID.rawValue,
            "generation": 1, "command": "discover", "catalog": ["generation": 1, "sources": [source]],
        ])
    }
}
