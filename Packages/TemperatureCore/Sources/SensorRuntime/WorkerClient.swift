import Foundation
import TemperatureCore

public struct WorkerClientConfiguration: Sendable, Equatable {
    public let executableURL: URL
    public let environment: [String: String]

    public init(executableURL: URL, environment: [String: String] = [:]) {
        precondition(executableURL.isFileURL, "worker executable must be an absolute file URL")
        self.executableURL = executableURL
        self.environment = environment
    }
}

public enum WorkerClientError: Error, Sendable, Equatable {
    case closed
    case requestInFlight
    case workerExitedUnexpectedly
    case endOfStream
    case unexpectedResponse
}

public actor WorkerClient: SensorTransport {
    private struct IOHandles: Sendable {
        let stdin: FileHandle
        let stdout: FileHandle
        let stderr: FileHandle
        let process: Process
    }

    private let configuration: WorkerClientConfiguration
    private let ioQueue = DispatchQueue(label: "org.temperature.worker-client.io")
    private var ioHandles: IOHandles?
    private var generation: UInt64 = 0
    private var inFlight = false
    private var closed = false
    private var requestOrdinal = 0

    public init(configuration: WorkerClientConfiguration) {
        self.configuration = configuration
    }

    public var connectionGeneration: UInt64 {
        generation
    }

    public var childProcessID: Int32? {
        ioHandles?.process.processIdentifier
    }

    public func discoverRaw() async throws -> DiscoveredCatalog {
        let response = try await perform(command: .discover)
        if case .failure(let failure) = response.payload {
            throw failure
        }
        guard case .catalog(let catalog) = response.payload else {
            throw WorkerClientError.unexpectedResponse
        }
        return catalog
    }

    public func readRaw(_ request: TransportReadRequest) async throws -> TransportReadBatch {
        guard request.generation == generation else {
            throw WorkerProtocol.monitorFailure(for: .generationMismatch, operation: "readRaw")
        }
        let wireRequest = WorkerProtocol.Request(
            requestID: request.requestID,
            generation: request.generation,
            command: .read,
            transportHandles: request.transportHandles,
            periodMS: request.requestedPeriodMS
        )
        let response = try await perform(wireRequest: wireRequest)
        if case .failure(let failure) = response.payload {
            throw failure
        }
        guard case .batch(let batch) = response.payload else {
            throw WorkerClientError.unexpectedResponse
        }
        return batch
    }

    public func close() async {
        guard !closed else { return }
        closed = true
        await shutdownProcess()
    }

    private func perform(command: WorkerCommand) async throws -> WorkerProtocol.Response {
        try await ensureProcessRunning()
        let wireRequest = WorkerProtocol.Request(
            requestID: try nextRequestID(),
            generation: generation,
            command: command
        )
        return try await perform(wireRequest: wireRequest)
    }

    private func perform(wireRequest: WorkerProtocol.Request) async throws -> WorkerProtocol.Response {
        guard !closed else { throw WorkerClientError.closed }
        guard !inFlight else { throw WorkerClientError.requestInFlight }
        inFlight = true
        defer { inFlight = false }

        try await ensureProcessRunning()
        guard wireRequest.generation == generation else {
            throw WorkerProtocol.monitorFailure(for: .generationMismatch, operation: wireRequest.command.rawValue)
        }
        guard let ioHandles else {
            throw WorkerClientError.workerExitedUnexpectedly
        }

        let requestData = try WorkerProtocol.encodeRequest(wireRequest)
        let responseData: Data
        do {
            responseData = try await ioQueueSubmit {
                try Self.writeRequest(requestData, to: ioHandles.stdin)
                return try Self.readResponseLine(from: ioHandles.stdout, process: ioHandles.process)
            }
        } catch let error as WorkerProtocolError {
            throw WorkerProtocol.monitorFailure(for: error, operation: wireRequest.command.rawValue)
        } catch WorkerClientError.endOfStream {
            await shutdownProcess()
            throw WorkerProtocol.protocolFailure(operation: wireRequest.command.rawValue, underlyingCode: "eof")
        } catch WorkerClientError.workerExitedUnexpectedly {
            await shutdownProcess()
            throw WorkerProtocol.protocolFailure(operation: wireRequest.command.rawValue, underlyingCode: "exit")
        } catch {
            await shutdownProcess()
            throw error
        }

        if ioHandles.process.isRunning == false {
            await shutdownProcess()
        }

        do {
            return try WorkerProtocol.decodeResponse(from: responseData, matching: wireRequest)
        } catch let error as WorkerProtocolError {
            throw WorkerProtocol.monitorFailure(for: error, operation: wireRequest.command.rawValue)
        }
    }

    private func nextRequestID() throws -> RequestID {
        requestOrdinal += 1
        return try RequestID(validating: String(format: "00000000-0000-4000-8000-%012d", requestOrdinal))
    }

    private func ensureProcessRunning() async throws {
        if ioHandles?.process.isRunning == true {
            return
        }
        try await spawnProcess()
    }

    private func spawnProcess() async throws {
        await shutdownProcess()
        generation &+= 1

        let process = Process()
        process.executableURL = configuration.executableURL
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in configuration.environment {
            environment[key] = value
        }
        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        ioHandles = IOHandles(
            stdin: stdinPipe.fileHandleForWriting,
            stdout: stdoutPipe.fileHandleForReading,
            stderr: stderrPipe.fileHandleForReading,
            process: process
        )
    }

    private func shutdownProcess() async {
        if let process = ioHandles?.process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }

        try? ioHandles?.stdin.close()
        try? ioHandles?.stdout.close()
        try? ioHandles?.stderr.close()
        ioHandles = nil
    }

    private func ioQueueSubmit<T: Sendable>(
        _ operation: @Sendable @escaping () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func writeRequest(_ requestData: Data, to handle: FileHandle) throws {
        var payload = requestData
        payload.append(0x0A)
        try handle.write(contentsOf: payload)
    }

    private static func readResponseLine(from handle: FileHandle, process: Process) throws -> Data {
        var buffer = Data()
        while buffer.firstIndex(of: 0x0A) == nil {
            if process.isRunning == false, buffer.isEmpty {
                throw WorkerClientError.workerExitedUnexpectedly
            }
            let chunk = handle.availableData
            if chunk.isEmpty {
                if buffer.isEmpty {
                    throw process.isRunning ? WorkerClientError.endOfStream : WorkerClientError.workerExitedUnexpectedly
                }
                break
            }
            buffer.append(chunk)
            if buffer.count > WorkerProtocol.frameLimitBytes + 1 {
                throw WorkerProtocolError.frameTooLarge
            }
        }
        guard let newlineIndex = buffer.firstIndex(of: 0x0A) else {
            return buffer
        }
        return Data(buffer[..<newlineIndex])
    }

}
