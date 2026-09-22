import Darwin
import Foundation
import TemperatureCore

public struct WorkerClientTimeouts: Sendable, Equatable {
    public let readDeadlineMS: Int
    public let discoverDeadlineMS: Int
    public let terminateGraceMS: Int

    public init(readDeadlineMS: Int, discoverDeadlineMS: Int, terminateGraceMS: Int) {
        precondition(readDeadlineMS > 0 && discoverDeadlineMS > 0 && terminateGraceMS > 0)
        self.readDeadlineMS = readDeadlineMS
        self.discoverDeadlineMS = discoverDeadlineMS
        self.terminateGraceMS = terminateGraceMS
    }

    public static let production = WorkerClientTimeouts(
        readDeadlineMS: 1_000,
        discoverDeadlineMS: 10_000,
        terminateGraceMS: 250
    )
}

public struct WorkerClientConfiguration: Sendable, Equatable {
    public let executableURL: URL
    public let environment: [String: String]
    public let timeouts: WorkerClientTimeouts

    public init(
        executableURL: URL,
        environment: [String: String] = [:],
        timeouts: WorkerClientTimeouts = .production
    ) {
        precondition(executableURL.isFileURL, "worker executable must be an absolute file URL")
        self.executableURL = executableURL
        self.environment = environment
        self.timeouts = timeouts
    }
}

public enum WorkerClientError: Error, Sendable, Equatable {
    case closed
    case requestInFlight
    case workerExitedUnexpectedly
    case endOfStream
    case unexpectedResponse
    case requestTimedOut
    case workerRecoveryFailed
}

public actor WorkerClient: SensorTransport, SensorConnectionGeneration {
    private struct IOHandles: Sendable {
        let stdin: FileHandle
        let stdout: FileHandle
        let stderr: FileHandle
        let process: Process
    }

    private static let stderrDrainBoundBytes = 65_536

    private let configuration: WorkerClientConfiguration
    private let ioQueue = DispatchQueue(label: "org.temperature.worker-client.io")
    private let stderrQueue = DispatchQueue(label: "org.temperature.worker-client.stderr")
    private var ioHandles: IOHandles?
    private var generation: UInt64 = 0
    private var inFlight = false
    private var closed = false
    private var recoveryDisabled = false
    private var requestOrdinal = 0

    public init(configuration: WorkerClientConfiguration) {
        self.configuration = configuration
    }

    public var connectionGeneration: UInt64 {
        generation
    }

    public func currentConnectionGeneration() async -> UInt64 {
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
        try? await terminateWorker()
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
        guard !recoveryDisabled else {
            throw WorkerProtocol.recoveryFailure(operation: wireRequest.command.rawValue)
        }
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

        let deadlineMS = wireRequest.command == .discover
            ? configuration.timeouts.discoverDeadlineMS
            : configuration.timeouts.readDeadlineMS
        let requestData = try WorkerProtocol.encodeRequest(wireRequest)
        let responseData: Data
        do {
            responseData = try await submitRequest(
                requestData: requestData,
                ioHandles: ioHandles,
                deadlineMS: deadlineMS
            )
        } catch WorkerClientError.requestTimedOut {
            try await handleTransportFailure(operation: wireRequest.command.rawValue, timedOut: true)
            throw WorkerProtocol.timeoutFailure(operation: wireRequest.command.rawValue)
        } catch let error as WorkerProtocolError {
            throw WorkerProtocol.monitorFailure(for: error, operation: wireRequest.command.rawValue)
        } catch WorkerClientError.endOfStream {
            try await handleTransportFailure(operation: wireRequest.command.rawValue, timedOut: false)
            throw WorkerProtocol.protocolFailure(operation: wireRequest.command.rawValue, underlyingCode: "eof")
        } catch WorkerClientError.workerExitedUnexpectedly {
            try await handleTransportFailure(operation: wireRequest.command.rawValue, timedOut: false)
            throw WorkerProtocol.protocolFailure(operation: wireRequest.command.rawValue, underlyingCode: "exit")
        } catch WorkerClientError.workerRecoveryFailed {
            recoveryDisabled = true
            throw WorkerProtocol.recoveryFailure(operation: wireRequest.command.rawValue)
        } catch {
            try? await handleTransportFailure(operation: wireRequest.command.rawValue, timedOut: false)
            throw error
        }

        if ioHandles.process.isRunning == false {
            try await handleTransportFailure(operation: wireRequest.command.rawValue, timedOut: false)
        }

        do {
            return try WorkerProtocol.decodeResponse(from: responseData, matching: wireRequest)
        } catch let error as WorkerProtocolError {
            throw WorkerProtocol.monitorFailure(for: error, operation: wireRequest.command.rawValue)
        }
    }

    private func handleTransportFailure(operation: String, timedOut: Bool) async throws {
        _ = operation
        _ = timedOut
        try await terminateWorker()
    }

    private func submitRequest(
        requestData: Data,
        ioHandles: IOHandles,
        deadlineMS: Int
    ) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await self.ioQueueSubmit {
                    try Self.writeRequest(requestData, to: ioHandles.stdin)
                    return try Self.readResponseLine(
                        from: ioHandles.stdout,
                        process: ioHandles.process,
                        deadlineMS: deadlineMS
                    )
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(deadlineMS + 100) * 1_000_000)
                try await self.interruptTransportIO()
                throw WorkerClientError.requestTimedOut
            }
            guard let response = try await group.next() else {
                throw WorkerClientError.requestTimedOut
            }
            group.cancelAll()
            return response
        }
    }

    private func interruptTransportIO() async throws {
        try? ioHandles?.stdin.close()
        try? ioHandles?.stdout.close()
        try? ioHandles?.stderr.close()
    }

    private func nextRequestID() throws -> RequestID {
        requestOrdinal += 1
        return try RequestID(validating: String(format: "00000000-0000-4000-8000-%012d", requestOrdinal))
    }

    private func ensureProcessRunning() async throws {
        if recoveryDisabled {
            throw WorkerProtocol.recoveryFailure(operation: "spawn")
        }
        if ioHandles?.process.isRunning == true {
            return
        }
        try await spawnProcess()
    }

    private func spawnProcess() async throws {
        try await terminateWorker()
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

        try? stdinPipe.fileHandleForReading.close()
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()

        let stderrReader = stderrPipe.fileHandleForReading
        ioHandles = IOHandles(
            stdin: stdinPipe.fileHandleForWriting,
            stdout: stdoutPipe.fileHandleForReading,
            stderr: stderrReader,
            process: process
        )
        stderrQueue.async {
            Self.drainStderr(stderrReader)
        }
    }

    private static func drainStderr(_ handle: FileHandle) {
        let fd = handle.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)
        var drainedBytes = 0
        var idlePolls = 0
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while drainedBytes <= stderrDrainBoundBytes, idlePolls < 2_000 {
            var pollFD = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let pollResult = poll(&pollFD, 1, 50)
            if pollResult < 0 {
                if errno == EINTR {
                    continue
                }
                return
            }
            if pollResult == 0 {
                idlePolls += 1
                continue
            }
            if pollFD.revents & Int16(POLLIN) == 0 {
                idlePolls += 1
                continue
            }
            idlePolls = 0
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                drainedBytes += count
                continue
            }
            if count == 0 {
                return
            }
            if errno == EINTR {
                continue
            }
            return
        }
    }

    private func terminateWorker() async throws {
        guard let handles = ioHandles else {
            return
        }

        let process = handles.process
        try await ioQueueSubmit {
            if process.isRunning {
                process.terminate()
            }

            let graceDeadline = DispatchTime.now() + .milliseconds(self.configuration.timeouts.terminateGraceMS)
            while process.isRunning && DispatchTime.now() < graceDeadline {
                Thread.sleep(forTimeInterval: 0.005)
            }

            kill(process.processIdentifier, SIGKILL)

            let exitDeadline = DispatchTime.now() + .milliseconds(self.configuration.timeouts.terminateGraceMS * 4)
            while process.isRunning && DispatchTime.now() < exitDeadline {
                Thread.sleep(forTimeInterval: 0.005)
            }

            if process.isRunning {
                throw WorkerClientError.workerRecoveryFailed
            }
        }

        try? handles.stdin.close()
        try? handles.stdout.close()
        try? handles.stderr.close()
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

    private static func readResponseLine(
        from handle: FileHandle,
        process: Process,
        deadlineMS: Int
    ) throws -> Data {
        var buffer = Data()
        let deadline = DispatchTime.now() + .milliseconds(deadlineMS)
        var idleSpins = 0
        let maxIdleSpins = max(deadlineMS / 2, 1) + 32

        while buffer.firstIndex(of: 0x0A) == nil {
            if DispatchTime.now() >= deadline {
                throw WorkerClientError.requestTimedOut
            }
            if idleSpins >= maxIdleSpins {
                throw WorkerClientError.requestTimedOut
            }
            if process.isRunning == false, buffer.isEmpty {
                throw WorkerClientError.workerExitedUnexpectedly
            }
            let chunk = handle.availableData
            if chunk.isEmpty {
                idleSpins += 1
                Thread.sleep(forTimeInterval: 0.002)
                continue
            }
            idleSpins = 0
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
