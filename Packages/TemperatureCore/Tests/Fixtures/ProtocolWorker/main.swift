import Darwin
import Foundation
import SensorRuntime
import TemperatureCore

enum ProtocolWorkerScenario: String {
    case success
    case oversize
    case badJSON
    case wrongID
    case oldGeneration
    case crash
    case hangDiscover
    case hangRead
    case ignoreTerm
    case lateRead
}

@main
struct ProtocolWorker {
    private static let stdoutHandle = FileHandle.standardOutput

    static func main() throws {
        let scenario = ProtocolWorkerScenario(
            rawValue: ProcessInfo.processInfo.environment["WORKER_SCENARIO"] ?? "success"
        ) ?? .success

        if scenario == .crash {
            exit(1)
        }

        if scenario == .ignoreTerm {
            signal(SIGTERM, SIG_IGN)
        }

        while let line = readLine(strippingNewline: true) {
            let requestData = Data(line.utf8)
            let request = try WorkerProtocol.decodeRequest(from: requestData)

            switch scenario {
            case .hangDiscover where request.command == .discover:
                while true {
                    Thread.sleep(forTimeInterval: 3600)
                }
            case .hangRead where request.command == .read:
                while true {
                    Thread.sleep(forTimeInterval: 3600)
                }
            case .ignoreTerm:
                while true {
                    Thread.sleep(forTimeInterval: 3600)
                }
            case .badJSON:
                try writeResponseLine("{not-json")
            case .oversize:
                try writeResponseLine(String(repeating: "x", count: WorkerProtocol.frameLimitBytes + 1))
            case .lateRead where request.command == .read:
                Thread.sleep(forTimeInterval: 2)
                fallthrough
            default:
                let response = try makeResponse(for: request, scenario: scenario)
                let responseData = try WorkerProtocol.encodeResponse(response)
                guard let responseLine = String(data: responseData, encoding: .utf8) else {
                    throw WorkerProtocolError.invalidJSON
                }
                try writeResponseLine(responseLine)
            }
        }
    }

    private static func writeResponseLine(_ line: String) throws {
        var payload = Data(line.utf8)
        payload.append(0x0A)
        try stdoutHandle.write(contentsOf: payload)
    }

    private static func makeResponse(
        for request: WorkerProtocol.Request,
        scenario: ProtocolWorkerScenario
    ) throws -> WorkerProtocol.Response {
        switch scenario {
        case .wrongID:
            let wrongID = try RequestID(validating: "00000000-0000-4000-8000-000000000999")
            return WorkerProtocol.Response(
                requestID: wrongID,
                generation: request.generation,
                command: request.command,
                payload: .closed
            )
        case .oldGeneration:
            return WorkerProtocol.Response(
                requestID: request.requestID,
                generation: request.generation &- 1,
                command: request.command,
                payload: .closed
            )
        case .success, .badJSON, .oversize, .crash, .hangDiscover, .hangRead, .ignoreTerm, .lateRead:
            break
        }

        switch request.command {
        case .discover:
            return WorkerProtocol.Response(
                requestID: request.requestID,
                generation: request.generation,
                command: .discover,
                payload: .catalog(
                    DiscoveredCatalog(
                        generation: request.generation,
                        sources: [
                            DiscoveredSource(
                                transportHandle: "smc:Tp01",
                                provider: .smc,
                                rawKey: "Tp01",
                                registryID: "fixture-reg-1",
                                encoding: "flt ",
                                byteCount: 4
                            )
                        ]
                    )
                )
            )
        case .read:
            return WorkerProtocol.Response(
                requestID: request.requestID,
                generation: request.generation,
                command: .read,
                payload: .batch(
                    TransportReadBatch(
                        requestID: request.requestID,
                        generation: request.generation,
                        readings: request.transportHandles.map { handle in
                            TransportReading(
                                transportHandle: handle,
                                started: Timestamp(elapsedNS: 0, wallUnixNS: 1_700_000_000_000_000_000),
                                finished: Timestamp(elapsedNS: 1_000_000, wallUnixNS: 1_700_000_000_001_000_000),
                                outcome: .success(valueC: 25.5, sourceWallUnixNS: nil, freshness: .unknown)
                            )
                        }
                    )
                )
            )
        case .close:
            return WorkerProtocol.Response(
                requestID: request.requestID,
                generation: request.generation,
                command: .close,
                payload: .closed
            )
        }
    }
}
