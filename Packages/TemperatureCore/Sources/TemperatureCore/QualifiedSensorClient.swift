import Foundation

public enum QualifiedSensorClientError: Error, Sendable, Equatable {
    case notDiscovered
    case unknownSourceID
    case generationMismatch
    case missingTransportReading
}

public actor QualifiedSensorClient: SensorClient {
    private let transport: any SensorTransport
    private let registry: any SourceRegistry
    private var catalog: QualifiedSourceCatalog?

    public init(transport: any SensorTransport, registry: any SourceRegistry) {
        self.transport = transport
        self.registry = registry
    }

    public var qualifiedCatalog: QualifiedSourceCatalog? {
        catalog
    }

    public func discover() async throws -> QualifiedSourceCatalog {
        do {
            let raw = try await transport.discoverRaw()
            let qualified = try registry.qualify(raw)
            catalog = qualified
            return qualified
        } catch {
            catalog = nil
            throw error
        }
    }

    public func read(_ request: ReadRequest) async throws -> ReadBatch {
        guard let activeCatalog = catalog else {
            throw QualifiedSensorClientError.notDiscovered
        }

        if let generational = transport as? any SensorConnectionGeneration {
            let liveGeneration = await generational.currentConnectionGeneration()
            if liveGeneration != activeCatalog.generation {
                self.catalog = nil
                throw QualifiedSensorClientError.generationMismatch
            }
        }

        var handles: [String] = []
        for sourceID in request.sourceIDs {
            guard let source = activeCatalog.available.first(where: { $0.sourceID == sourceID }) else {
                throw MonitorFailure(
                    code: .sensorTag,
                    severity: .capability,
                    component: "QualifiedSensorClient",
                    operation: "read",
                    retryCount: 0,
                    sourceID: sourceID,
                    underlyingCode: "unknown_source_id"
                )
            }
            guard source.connectionGeneration == activeCatalog.generation else {
                throw QualifiedSensorClientError.generationMismatch
            }
            handles.append(source.transportHandle)
        }

        do {
            let transportBatch = try await transport.readRaw(
                TransportReadRequest(
                    requestID: request.requestID,
                    generation: activeCatalog.generation,
                    transportHandles: handles,
                    requestedPeriodMS: request.requestedPeriodMS
                )
            )

            guard transportBatch.generation == activeCatalog.generation else {
                self.catalog = nil
                throw QualifiedSensorClientError.generationMismatch
            }

            var readings: [Reading] = []
            for (sourceID, handle) in zip(request.sourceIDs, handles) {
                guard let transportReading = transportBatch.readings.first(where: { $0.transportHandle == handle }) else {
                    throw QualifiedSensorClientError.missingTransportReading
                }
                readings.append(
                    Reading(
                        sourceID: sourceID,
                        started: transportReading.started,
                        finished: transportReading.finished,
                        outcome: mapOutcome(transportReading.outcome)
                    )
                )
            }

            return ReadBatch(
                requestID: request.requestID,
                generation: activeCatalog.generation,
                readings: readings
            )
        } catch {
            if errorInvalidatesCatalog(error) {
                self.catalog = nil
            }
            throw error
        }
    }

    private func errorInvalidatesCatalog(_ error: Error) -> Bool {
        if error is QualifiedSensorClientError {
            return true
        }
        if let failure = error as? MonitorFailure {
            return failure.code == .sensorTimeout || failure.code == .sensorProtocol
        }
        return false
    }

    public func close() async {
        catalog = nil
        await transport.close()
    }

    private func mapOutcome(_ outcome: TransportReadingOutcome) -> ReadingOutcome {
        switch outcome {
        case .success(let valueC, let sourceWallUnixNS, let freshness):
            return .success(valueC: valueC, sourceWallUnixNS: sourceWallUnixNS, freshness: freshness)
        case .failure(let code, let underlyingCode):
            return .failure(
                MonitorFailure(
                    code: code,
                    severity: .degraded,
                    component: "SensorWorker",
                    operation: "read",
                    retryCount: 0,
                    sourceID: nil,
                    underlyingCode: underlyingCode
                )
            )
        }
    }
}
