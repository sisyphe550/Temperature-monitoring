import Foundation
import Testing
@testable import SensorRuntime
import TemperatureCore

@Suite struct WorkerProtocolTests {
    private func requestID(_ ordinal: Int) throws -> RequestID {
        try RequestID(validating: String(format: "00000000-0000-4000-8000-%012d", ordinal))
    }

    @Test func discoverAndReadRoundTrip() throws {
        let discoverRequest = WorkerProtocol.Request(
            requestID: try requestID(201),
            generation: 1,
            command: .discover
        )
        let discoverData = try WorkerProtocol.encodeRequest(discoverRequest)
        let decodedDiscover = try WorkerProtocol.decodeRequest(from: discoverData)
        #expect(decodedDiscover == discoverRequest)
        #expect(!String(data: discoverData, encoding: .utf8)!.contains("sourceID"))

        let discoverResponse = WorkerProtocol.Response(
            requestID: discoverRequest.requestID,
            generation: 1,
            command: .discover,
            payload: .catalog(
                DiscoveredCatalog(
                    generation: 1,
                    sources: [
                        DiscoveredSource(
                            transportHandle: "smc:Tp01",
                            provider: .smc,
                            rawKey: "Tp01",
                            registryID: nil,
                            encoding: "flt ",
                            byteCount: 4
                        )
                    ]
                )
            )
        )
        let discoverResponseData = try WorkerProtocol.encodeResponse(discoverResponse)
        let decodedDiscoverResponse = try WorkerProtocol.decodeResponse(
            from: discoverResponseData,
            matching: discoverRequest
        )
        if case .catalog(let catalog) = decodedDiscoverResponse.payload {
            #expect(catalog.generation == 1)
            #expect(catalog.sources.count == 1)
        } else {
            Issue.record("expected catalog payload")
        }

        let readRequest = WorkerProtocol.Request(
            requestID: try requestID(202),
            generation: 1,
            command: .read,
            transportHandles: ["smc:Tp01"],
            periodMS: 200
        )
        let readData = try WorkerProtocol.encodeRequest(readRequest)
        #expect(String(data: readData, encoding: .utf8) == """
{"command":"read","generation":1,"periodMS":200,"requestID":"00000000-0000-4000-8000-000000000202","transportHandles":["smc:Tp01"],"version":1}
""")
        let transportRequest = try WorkerProtocol.transportReadRequest(from: readRequest)
        #expect(transportRequest.requestedPeriodMS == 200)

        let readResponse = WorkerProtocol.Response(
            requestID: readRequest.requestID,
            generation: 1,
            command: .read,
            payload: .batch(
                TransportReadBatch(
                    requestID: readRequest.requestID,
                    generation: 1,
                    readings: [
                        TransportReading(
                            transportHandle: "smc:Tp01",
                            started: Timestamp(elapsedNS: 0, wallUnixNS: 1),
                            finished: Timestamp(elapsedNS: 1_000_000, wallUnixNS: 2),
                            outcome: .success(valueC: 25.5, sourceWallUnixNS: nil, freshness: .unknown)
                        )
                    ]
                )
            )
        )
        let readResponseData = try WorkerProtocol.encodeResponse(readResponse)
        let decodedReadResponse = try WorkerProtocol.decodeResponse(
            from: readResponseData,
            matching: readRequest
        )
        if case .batch(let batch) = decodedReadResponse.payload {
            #expect(batch.readings.count == 1)
            #expect(batch.readings[0].outcome == .success(valueC: 25.5, sourceWallUnixNS: nil, freshness: .unknown))
        } else {
            Issue.record("expected batch payload")
        }
    }

    @Test func rejectsNonCanonicalUUID() {
        let malformed = Data("""
        {"version":1,"requestID":"not-a-uuid","generation":1,"command":"discover"}
        """.utf8)
        #expect(throws: IdentifierError.self) {
            _ = try WorkerProtocol.decodeRequest(from: malformed)
        }

        let uppercase = Data("""
        {"version":1,"requestID":"00000000-0000-4000-8000-0000000000AB","generation":1,"command":"discover"}
        """.utf8)
        #expect(throws: IdentifierError.self) {
            _ = try WorkerProtocol.decodeRequest(from: uppercase)
        }
    }

    @Test func rejectsBadJSON() {
        #expect(throws: WorkerProtocolError.invalidJSON) {
            _ = try WorkerProtocol.decodeRequest(from: Data("{".utf8))
        }
    }

    @Test func rejectsOversizeFrame() {
        let oversized = Data(repeating: 0x20, count: WorkerProtocol.frameLimitBytes + 1)
        #expect(throws: WorkerProtocolError.frameTooLarge) {
            _ = try WorkerProtocol.decodeRequest(from: oversized)
        }
    }

    @Test func rejectsWrongVersion() {
        let json = Data("""
        {"version":2,"requestID":"00000000-0000-4000-8000-000000000201","generation":1,"command":"discover"}
        """.utf8)
        #expect(throws: WorkerProtocolError.invalidVersion) {
            _ = try WorkerProtocol.decodeRequest(from: json)
        }
    }

    @Test func rejectsUnknownCommand() {
        let json = Data("""
        {"version":1,"requestID":"00000000-0000-4000-8000-000000000201","generation":1,"command":"ping"}
        """.utf8)
        #expect(throws: WorkerProtocolError.unknownCommand("ping")) {
            _ = try WorkerProtocol.decodeRequest(from: json)
        }
    }

    @Test func rejectsResponseRequestIDMismatch() throws {
        let request = WorkerProtocol.Request(
            requestID: try requestID(201),
            generation: 1,
            command: .close
        )
        let response = WorkerProtocol.Response(
            requestID: try requestID(999),
            generation: 1,
            command: .close,
            payload: .closed
        )
        let data = try WorkerProtocol.encodeResponse(response)
        #expect(throws: WorkerProtocolError.requestIDMismatch) {
            _ = try WorkerProtocol.decodeResponse(from: data, matching: request)
        }
    }

    @Test func rejectsResponseGenerationMismatch() throws {
        let request = WorkerProtocol.Request(
            requestID: try requestID(201),
            generation: 2,
            command: .close
        )
        let response = WorkerProtocol.Response(
            requestID: request.requestID,
            generation: 1,
            command: .close,
            payload: .closed
        )
        let data = try WorkerProtocol.encodeResponse(response)
        #expect(throws: WorkerProtocolError.generationMismatch) {
            _ = try WorkerProtocol.decodeResponse(from: data, matching: request)
        }
    }

    @Test func rejectsSourceIDOnWire() {
        let json = Data("""
        {"version":1,"requestID":"00000000-0000-4000-8000-000000000201","generation":1,"command":"read","transportHandles":["smc:Tp01"],"periodMS":200,"sourceID":"00000000-0000-4000-8000-000000000001"}
        """.utf8)
        #expect(throws: WorkerProtocolError.forbiddenWireKey("sourceID")) {
            _ = try WorkerProtocol.decodeRequest(from: json)
        }
    }

    @Test func rejectsFloatingPointGeneration() {
        let json = Data("""
        {"version":1,"requestID":"00000000-0000-4000-8000-000000000201","generation":1.5,"command":"discover"}
        """.utf8)
        #expect(throws: WorkerProtocolError.integerFieldNotIntegral("generation")) {
            _ = try WorkerProtocol.decodeRequest(from: json)
        }
    }

    @Test func protocolFailureUsesSensorProtocolCode() {
        let failure = WorkerProtocol.protocolFailure(operation: "decodeRequest")
        #expect(failure.code == .sensorProtocol)
        #expect(failure.severity == .fatal)
    }
}
