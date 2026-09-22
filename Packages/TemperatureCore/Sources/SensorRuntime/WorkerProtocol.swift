import CoreFoundation
import Foundation
import TemperatureCore

public enum WorkerCommand: String, Codable, Sendable, Equatable {
    case discover
    case read
    case close
}

public enum WorkerProtocolError: Error, Sendable, Equatable {
    case frameTooLarge
    case invalidJSON
    case invalidVersion
    case invalidRequestID(String)
    case missingField(String)
    case unexpectedField(String)
    case unknownCommand(String)
    case integerFieldNotIntegral(String)
    case forbiddenWireKey(String)
    case requestIDMismatch
    case generationMismatch
    case invalidResponsePayload
}

public enum WorkerProtocol {
    public static let frameLimitBytes = 1_048_576

    public struct Request: Sendable, Equatable {
        public let requestID: RequestID
        public let generation: UInt64
        public let command: WorkerCommand
        public let transportHandles: [String]
        public let periodMS: Int

        public init(
            requestID: RequestID,
            generation: UInt64,
            command: WorkerCommand,
            transportHandles: [String] = [],
            periodMS: Int = 0
        ) {
            self.requestID = requestID
            self.generation = generation
            self.command = command
            self.transportHandles = transportHandles
            self.periodMS = periodMS
        }
    }

    public enum ResponsePayload: Sendable, Equatable {
        case catalog(DiscoveredCatalog)
        case batch(TransportReadBatch)
        case closed
        case failure(MonitorFailure)
    }

    public struct Response: Sendable, Equatable {
        public let requestID: RequestID
        public let generation: UInt64
        public let command: WorkerCommand
        public let payload: ResponsePayload

        public init(
            requestID: RequestID,
            generation: UInt64,
            command: WorkerCommand,
            payload: ResponsePayload
        ) {
            self.requestID = requestID
            self.generation = generation
            self.command = command
            self.payload = payload
        }
    }

    public static func encodeRequest(_ request: Request) throws -> Data {
        var object: [String: Any] = [
            "version": 1,
            "requestID": request.requestID.rawValue,
            "generation": NSNumber(value: request.generation),
            "command": request.command.rawValue,
        ]
        switch request.command {
        case .read:
            object["transportHandles"] = request.transportHandles
            object["periodMS"] = NSNumber(value: request.periodMS)
        case .discover, .close:
            break
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try validateFrameSize(data)
        return data
    }

    public static func decodeRequest(from data: Data) throws -> Request {
        try validateFrameSize(data)
        let object = try parseJSONObject(from: data)
        try rejectForbiddenWireKeys(in: object)
        guard try jsonInteger(at: object, key: "version") == 1 else {
            throw WorkerProtocolError.invalidVersion
        }
        let requestID = try RequestID(validating: try jsonString(at: object, key: "requestID"))
        let generation = try jsonUInt64(at: object, key: "generation")
        let command = try parseCommand(try jsonString(at: object, key: "command"))
        switch command {
        case .read:
            let handles = try jsonStringArray(at: object, key: "transportHandles")
            let periodMS = try jsonInt(at: object, key: "periodMS")
            if object["catalog"] != nil || object["batch"] != nil || object["failure"] != nil {
                throw WorkerProtocolError.unexpectedField("response-only field on request")
            }
            return Request(
                requestID: requestID,
                generation: generation,
                command: command,
                transportHandles: handles,
                periodMS: periodMS
            )
        case .discover, .close:
            for key in ["transportHandles", "periodMS", "catalog", "batch", "failure"] {
                if object[key] != nil {
                    throw WorkerProtocolError.unexpectedField(key)
                }
            }
            return Request(
                requestID: requestID,
                generation: generation,
                command: command
            )
        }
    }

    public static func encodeResponse(_ response: Response) throws -> Data {
        var object: [String: Any] = [
            "version": 1,
            "requestID": response.requestID.rawValue,
            "generation": NSNumber(value: response.generation),
            "command": response.command.rawValue,
        ]
        switch response.payload {
        case .catalog(let catalog):
            object["catalog"] = try catalogJSONObject(catalog)
        case .batch(let batch):
            object["batch"] = try batchJSONObject(batch)
        case .closed:
            break
        case .failure(let failure):
            object["failure"] = failureJSONObject(failure)
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try validateFrameSize(data)
        return data
    }

    public static func decodeResponse(from data: Data, matching request: Request) throws -> Response {
        try validateFrameSize(data)
        let object = try parseJSONObject(from: data)
        try rejectForbiddenWireKeys(in: object)
        guard try jsonInteger(at: object, key: "version") == 1 else {
            throw WorkerProtocolError.invalidVersion
        }
        let requestID = try RequestID(validating: try jsonString(at: object, key: "requestID"))
        guard requestID == request.requestID else {
            throw WorkerProtocolError.requestIDMismatch
        }
        let generation = try jsonUInt64(at: object, key: "generation")
        guard generation == request.generation else {
            throw WorkerProtocolError.generationMismatch
        }
        let command = try parseCommand(try jsonString(at: object, key: "command"))
        guard command == request.command else {
            throw WorkerProtocolError.invalidResponsePayload
        }
        if let failureObject = object["failure"] as? [String: Any] {
            return Response(
                requestID: requestID,
                generation: generation,
                command: command,
                payload: .failure(try decodeFailure(failureObject))
            )
        }
        switch command {
        case .discover:
            guard let catalogObject = object["catalog"] as? [String: Any] else {
                throw WorkerProtocolError.missingField("catalog")
            }
            return Response(
                requestID: requestID,
                generation: generation,
                command: command,
                payload: .catalog(try decodeCatalog(catalogObject))
            )
        case .read:
            guard let batchObject = object["batch"] as? [String: Any] else {
                throw WorkerProtocolError.missingField("batch")
            }
            return Response(
                requestID: requestID,
                generation: generation,
                command: command,
                payload: .batch(try decodeBatch(batchObject, requestID: requestID, generation: generation))
            )
        case .close:
            return Response(
                requestID: requestID,
                generation: generation,
                command: command,
                payload: .closed
            )
        }
    }

    public static func transportReadRequest(from request: Request) throws -> TransportReadRequest {
        guard request.command == .read else {
            throw WorkerProtocolError.invalidResponsePayload
        }
        return TransportReadRequest(
            requestID: request.requestID,
            generation: request.generation,
            transportHandles: request.transportHandles,
            requestedPeriodMS: request.periodMS
        )
    }

    public static func protocolFailure(
        operation: String,
        underlyingCode: String? = nil
    ) -> MonitorFailure {
        MonitorFailure(
            code: .sensorProtocol,
            severity: .fatal,
            component: "SensorRuntime",
            operation: operation,
            retryCount: 0,
            sourceID: nil,
            underlyingCode: underlyingCode
        )
    }

    public static func timeoutFailure(operation: String) -> MonitorFailure {
        MonitorFailure(
            code: .sensorTimeout,
            severity: .degraded,
            component: "SensorRuntime",
            operation: operation,
            retryCount: 0,
            sourceID: nil,
            underlyingCode: "deadline_exceeded"
        )
    }

    public static func recoveryFailure(operation: String) -> MonitorFailure {
        MonitorFailure(
            code: .appInit,
            severity: .fatal,
            component: "SensorRuntime",
            operation: operation,
            retryCount: 0,
            sourceID: nil,
            underlyingCode: "worker_recovery_failed"
        )
    }

    public static func monitorFailure(for error: WorkerProtocolError, operation: String) -> MonitorFailure {
        protocolFailure(operation: operation, underlyingCode: String(describing: error))
    }
}

private extension WorkerProtocol {
    static func validateFrameSize(_ data: Data) throws {
        if data.count > frameLimitBytes {
            throw WorkerProtocolError.frameTooLarge
        }
    }

    static func parseJSONObject(from data: Data) throws -> [String: Any] {
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw WorkerProtocolError.invalidJSON
            }
            return object
        } catch let error as WorkerProtocolError {
            throw error
        } catch {
            throw WorkerProtocolError.invalidJSON
        }
    }

    static func rejectForbiddenWireKeys(in value: Any, path: String = "") throws {
        if let object = value as? [String: Any] {
            for (key, nested) in object {
                let nextPath = path.isEmpty ? key : "\(path).\(key)"
                if key == "sourceID" || key == "sourceIDs" || key == "memberSourceIDs" {
                    throw WorkerProtocolError.forbiddenWireKey(nextPath)
                }
                try rejectForbiddenWireKeys(in: nested, path: nextPath)
            }
        } else if let array = value as? [Any] {
            for (index, nested) in array.enumerated() {
                try rejectForbiddenWireKeys(in: nested, path: "\(path)[\(index)]")
            }
        }
    }

    static func parseCommand(_ raw: String) throws -> WorkerCommand {
        guard let command = WorkerCommand(rawValue: raw) else {
            throw WorkerProtocolError.unknownCommand(raw)
        }
        return command
    }

    static func jsonString(at object: [String: Any], key: String) throws -> String {
        guard let value = object[key] as? String else {
            throw WorkerProtocolError.missingField(key)
        }
        return value
    }

    static func jsonStringArray(at object: [String: Any], key: String) throws -> [String] {
        guard let value = object[key] as? [String] else {
            throw WorkerProtocolError.missingField(key)
        }
        return value
    }

    static func jsonInteger(at object: [String: Any], key: String) throws -> Int {
        guard let number = object[key] as? NSNumber, number.isInteger() else {
            throw WorkerProtocolError.integerFieldNotIntegral(key)
        }
        return number.intValue
    }

    static func jsonInt(at object: [String: Any], key: String) throws -> Int {
        try jsonInteger(at: object, key: key)
    }

    static func jsonUInt64(at object: [String: Any], key: String) throws -> UInt64 {
        guard let number = object[key] as? NSNumber, number.isInteger(), number.compare(0) != .orderedAscending else {
            throw WorkerProtocolError.integerFieldNotIntegral(key)
        }
        let value = number.uint64Value
        if String(value) != number.stringValue, number.intValue < 0 {
            throw WorkerProtocolError.integerFieldNotIntegral(key)
        }
        return value
    }

    static func catalogJSONObject(_ catalog: DiscoveredCatalog) throws -> [String: Any] {
        [
            "generation": NSNumber(value: catalog.generation),
            "sources": try catalog.sources.map(sourceJSONObject),
        ]
    }

    static func sourceJSONObject(_ source: DiscoveredSource) throws -> [String: Any] {
        var object: [String: Any] = [
            "transportHandle": source.transportHandle,
            "provider": source.provider.rawValue,
            "rawKey": source.rawKey,
            "encoding": source.encoding,
            "byteCount": NSNumber(value: source.byteCount),
        ]
        if let registryID = source.registryID {
            object["registryID"] = registryID
        }
        return object
    }

    static func batchJSONObject(_ batch: TransportReadBatch) throws -> [String: Any] {
        [
            "requestID": batch.requestID.rawValue,
            "generation": NSNumber(value: batch.generation),
            "readings": try batch.readings.map(readingJSONObject),
        ]
    }

    static func readingJSONObject(_ reading: TransportReading) throws -> [String: Any] {
        var outcome: [String: Any]
        switch reading.outcome {
        case .success(let valueC, let sourceWallUnixNS, let freshness):
            outcome = [
                "kind": "success",
                "valueC": valueC,
                "freshness": freshness.rawValue,
            ]
            if let sourceWallUnixNS {
                outcome["sourceWallUnixNS"] = NSNumber(value: sourceWallUnixNS)
            }
        case .failure(let code, let underlyingCode):
            outcome = [
                "kind": "failure",
                "code": code.rawValue,
            ]
            if let underlyingCode {
                outcome["underlyingCode"] = underlyingCode
            }
        }
        return [
            "transportHandle": reading.transportHandle,
            "started": timestampJSONObject(reading.started),
            "finished": timestampJSONObject(reading.finished),
            "outcome": outcome,
        ]
    }

    static func timestampJSONObject(_ timestamp: Timestamp) -> [String: Any] {
        [
            "elapsedNS": NSNumber(value: timestamp.elapsedNS),
            "wallUnixNS": NSNumber(value: timestamp.wallUnixNS),
        ]
    }

    static func failureJSONObject(_ failure: MonitorFailure) -> [String: Any] {
        var object: [String: Any] = [
            "code": failure.code.rawValue,
            "severity": failure.severity.rawValue,
            "component": failure.component,
            "operation": failure.operation,
            "retryCount": NSNumber(value: failure.retryCount),
        ]
        if let underlyingCode = failure.underlyingCode {
            object["underlyingCode"] = underlyingCode
        }
        return object
    }

    static func decodeCatalog(_ object: [String: Any]) throws -> DiscoveredCatalog {
        let generation = try jsonUInt64(at: object, key: "generation")
        guard let sourcesArray = object["sources"] as? [[String: Any]] else {
            throw WorkerProtocolError.missingField("sources")
        }
        let sources = try sourcesArray.map(decodeSource)
        return DiscoveredCatalog(generation: generation, sources: sources)
    }

    static func decodeSource(_ object: [String: Any]) throws -> DiscoveredSource {
        let providerRaw = try jsonString(at: object, key: "provider")
        guard let provider = ProviderKind(rawValue: providerRaw) else {
            throw WorkerProtocolError.invalidResponsePayload
        }
        return DiscoveredSource(
            transportHandle: try jsonString(at: object, key: "transportHandle"),
            provider: provider,
            rawKey: try jsonString(at: object, key: "rawKey"),
            registryID: object["registryID"] as? String,
            encoding: try jsonString(at: object, key: "encoding"),
            byteCount: try jsonInt(at: object, key: "byteCount")
        )
    }

    static func decodeBatch(
        _ object: [String: Any],
        requestID: RequestID,
        generation: UInt64
    ) throws -> TransportReadBatch {
        let decodedRequestID = try RequestID(validating: try jsonString(at: object, key: "requestID"))
        guard decodedRequestID == requestID else {
            throw WorkerProtocolError.requestIDMismatch
        }
        let decodedGeneration = try jsonUInt64(at: object, key: "generation")
        guard decodedGeneration == generation else {
            throw WorkerProtocolError.generationMismatch
        }
        guard let readingsArray = object["readings"] as? [[String: Any]] else {
            throw WorkerProtocolError.missingField("readings")
        }
        let readings = try readingsArray.map(decodeReading)
        return TransportReadBatch(requestID: requestID, generation: generation, readings: readings)
    }

    static func decodeReading(_ object: [String: Any]) throws -> TransportReading {
        guard let outcomeObject = object["outcome"] as? [String: Any] else {
            throw WorkerProtocolError.missingField("outcome")
        }
        let kind = try jsonString(at: outcomeObject, key: "kind")
        let outcome: TransportReadingOutcome
        switch kind {
        case "success":
            guard let valueC = outcomeObject["valueC"] as? Double else {
                throw WorkerProtocolError.invalidResponsePayload
            }
            let sourceWallUnixNS: Int64?
            if let wallNumber = outcomeObject["sourceWallUnixNS"] as? NSNumber, wallNumber.isInteger() {
                sourceWallUnixNS = wallNumber.int64Value
            } else {
                sourceWallUnixNS = nil
            }
            outcome = .success(
                valueC: valueC,
                sourceWallUnixNS: sourceWallUnixNS,
                freshness: Freshness(rawValue: try jsonString(at: outcomeObject, key: "freshness")) ?? .unknown
            )
        case "failure":
            guard let code = MonitorErrorCode(rawValue: try jsonString(at: outcomeObject, key: "code")) else {
                throw WorkerProtocolError.invalidResponsePayload
            }
            outcome = .failure(code: code, underlyingCode: outcomeObject["underlyingCode"] as? String)
        default:
            throw WorkerProtocolError.invalidResponsePayload
        }
        return TransportReading(
            transportHandle: try jsonString(at: object, key: "transportHandle"),
            started: try decodeTimestamp(object["started"] as? [String: Any] ?? [:]),
            finished: try decodeTimestamp(object["finished"] as? [String: Any] ?? [:]),
            outcome: outcome
        )
    }

    static func decodeTimestamp(_ object: [String: Any]) throws -> Timestamp {
        Timestamp(
            elapsedNS: Int64(try jsonInt(at: object, key: "elapsedNS")),
            wallUnixNS: Int64(try jsonInt(at: object, key: "wallUnixNS"))
        )
    }

    static func decodeFailure(_ object: [String: Any]) throws -> MonitorFailure {
        guard let code = MonitorErrorCode(rawValue: try jsonString(at: object, key: "code")) else {
            throw WorkerProtocolError.invalidResponsePayload
        }
        guard let severity = Severity(rawValue: try jsonString(at: object, key: "severity")) else {
            throw WorkerProtocolError.invalidResponsePayload
        }
        return MonitorFailure(
            code: code,
            severity: severity,
            component: try jsonString(at: object, key: "component"),
            operation: try jsonString(at: object, key: "operation"),
            retryCount: try jsonInt(at: object, key: "retryCount"),
            sourceID: nil,
            underlyingCode: object["underlyingCode"] as? String
        )
    }
}

private extension NSNumber {
    func isInteger() -> Bool {
        CFGetTypeID(self) == CFNumberGetTypeID() && CFNumberIsFloatType(self) == false
    }
}
