import Darwin
import Foundation
import SensorRuntime
import TemperatureCore

@main
struct SensorWorkerEntry {
    private static let stdoutHandle = FileHandle.standardOutput
    private static nonisolated(unsafe) let session = HardwareSession()

    static func main() throws {
        while let line = readLine(strippingNewline: true) {
            let requestData = Data(line.utf8)
            let request = try WorkerProtocol.decodeRequest(from: requestData)
            let response = try makeResponse(for: request)
            let responseData = try WorkerProtocol.encodeResponse(response)
            guard let responseLine = String(data: responseData, encoding: .utf8) else {
                throw WorkerProtocolError.invalidJSON
            }
            try writeResponseLine(responseLine)
        }
        session.closeConnections()
    }

    private static func writeResponseLine(_ line: String) throws {
        var payload = Data(line.utf8)
        payload.append(0x0A)
        try stdoutHandle.write(contentsOf: payload)
    }

    private static func makeResponse(for request: WorkerProtocol.Request) throws -> WorkerProtocol.Response {
        switch request.command {
        case .discover:
            let catalog = session.discover(generation: request.generation)
            return WorkerProtocol.Response(
                requestID: request.requestID,
                generation: request.generation,
                command: .discover,
                payload: .catalog(catalog)
            )
        case .read:
            let batch = session.read(
                requestID: request.requestID,
                generation: request.generation,
                transportHandles: request.transportHandles
            )
            return WorkerProtocol.Response(
                requestID: request.requestID,
                generation: request.generation,
                command: .read,
                payload: .batch(batch)
            )
        case .close:
            session.closeConnections()
            return WorkerProtocol.Response(
                requestID: request.requestID,
                generation: request.generation,
                command: .close,
                payload: .closed
            )
        }
    }
}
