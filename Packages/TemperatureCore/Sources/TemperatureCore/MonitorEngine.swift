import Foundation

public actor MonitorEngine: ProcessingEngine {
    private struct ProcessedRequest: Equatable {
        let fingerprint: String
        let receipt: ProcessingReceipt
    }

    private struct SeriesState {
        var segment: Int64
        var lastElapsedNS: Int64
    }

    private let clock: MonitorClock
    private let commit: PersistenceCommitCapability
    private let sessionID: SessionID
    private let configuration: RuntimeConfiguration
    private let sourceToSeries: [SourceID: SeriesDefinition]
    private let emaProcessor: EMAProcessor
    private var buffers: RingBufferStore
    private var seriesState: [SeriesID: SeriesState]
    private var lastEMABySeries: [SeriesID: EMAValue] = [:]
    private var acceptedGeneration: UInt64 = 0
    private var nextSampleSequence: Int64 = 1
    private var deliveredSampleIDs: Set<String> = []
    private var processedRequests: [RequestID: ProcessedRequest] = [:]
    private var snapshotGeneration: UInt64 = 0
    private var cpuPeriodMS: Int

    public init(
        clock: MonitorClock,
        commit: PersistenceCommitCapability,
        session: SessionMetadata,
        configuration: RuntimeConfiguration,
        definitions: [SeriesDefinition],
        cpuPeriodMS: Int
    ) {
        self.clock = clock
        self.commit = commit
        sessionID = session.sessionID
        self.configuration = configuration
        sourceToSeries = Dictionary(
            uniqueKeysWithValues: definitions.flatMap { definition in
                definition.memberSourceIDs.map { ($0, definition) }
            }
        )
        emaProcessor = EMAProcessor(tauSeconds: configuration.emaTauSeconds)
        buffers = RingBufferStore(
            configuration: RingBufferConfiguration(
                capacity: configuration.ringCapacityPerSeries,
                retentionSeconds: configuration.retentionSeconds.raw
            ),
            maxActiveSeries: configuration.maxActiveSeries
        )
        seriesState = Dictionary(
            uniqueKeysWithValues: definitions.map {
                ($0.seriesID, SeriesState(segment: 1, lastElapsedNS: Int64.min))
            }
        )
        self.cpuPeriodMS = cpuPeriodMS
        for definition in definitions {
            try? buffers.registerSeries(definition.seriesID)
        }
    }

    public func accept(_ batch: ReadBatch, lease: PersistenceLease) async throws -> ProcessingReceipt {
        try validateLease(lease, for: batch)
        if let processed = processedRequests[batch.requestID] {
            let fingerprint = Self.fingerprint(for: batch)
            guard processed.fingerprint == fingerprint else {
                throw Self.failure(
                    code: .databaseIntegrity,
                    operation: "accept",
                    underlyingCode: "request_content_mismatch"
                )
            }
            return processed.receipt
        }

        guard batch.generation >= acceptedGeneration else {
            throw Self.failure(
                code: .processingValidate,
                operation: "accept",
                underlyingCode: "stale_generation"
            )
        }
        acceptedGeneration = max(acceptedGeneration, batch.generation)

        let now = clock.now()
        var rawSamples: [Sample] = []
        var emaSamples: [EMAValue] = []
        for reading in batch.readings {
            switch reading.outcome {
            case .failure:
                continue
            case let .success(valueC, sourceWallUnixNS, freshness):
                do {
                    try SampleValidation.validateSuccessValue(valueC)
                } catch ProcessingValidationError.invalidTemperature {
                    throw Self.failure(
                        code: .processingValidate,
                        operation: "accept",
                        underlyingCode: "invalid_temperature"
                    )
                }
                guard let definition = sourceToSeries[reading.sourceID] else {
                    throw Self.failure(
                        code: .processingValidate,
                        operation: "accept",
                        underlyingCode: "unknown_source"
                    )
                }
                let elapsedNS = reading.finished.elapsedNS
                var state = seriesState[definition.seriesID] ?? SeriesState(segment: 1, lastElapsedNS: Int64.min)
                if elapsedNS < state.lastElapsedNS {
                    continue
                }
                if elapsedNS == state.lastElapsedNS {
                    throw Self.failure(
                        code: .processingValidate,
                        operation: "accept",
                        underlyingCode: "non_monotonic_elapsed"
                    )
                }
                let sampleID = Self.makeSampleID(sessionID: sessionID, sequence: nextSampleSequence)
                nextSampleSequence += 1
                if deliveredSampleIDs.contains(sampleID) {
                    throw Self.failure(
                        code: .processingValidate,
                        operation: "accept",
                        underlyingCode: "duplicate_sample_id"
                    )
                }
                let sample = Sample(
                    sampleID: sampleID,
                    seriesID: definition.seriesID,
                    segment: state.segment,
                    timestamp: reading.finished,
                    periodMS: batch.requestedPeriodMS(from: reading),
                    valueC: valueC,
                    freshness: freshness,
                    sourceWallUnixNS: sourceWallUnixNS,
                    memberSampleIDs: []
                )
                rawSamples.append(sample)
                let ema = try computeEMA(for: sample, kind: definition.kind)
                emaSamples.append(ema)
                state.lastElapsedNS = elapsedNS
                seriesState[definition.seriesID] = state
            }
        }

        let batchID = BatchID(UUID())
        let persistenceBatch = PersistenceBatch(
            batchID: batchID,
            sources: [],
            definitions: [],
            segments: [],
            raw: rawSamples,
            ema: emaSamples,
            buckets: [],
            trends: [],
            gaps: []
        )

        let receipt = try await commit.commit(persistenceBatch, using: lease)
        try validateReceipt(receipt, for: persistenceBatch)

        let bufferNow = max(now.elapsedNS, rawSamples.map(\.timestamp.elapsedNS).max() ?? now.elapsedNS)
        for sample in rawSamples {
            try buffers.appendRaw(sample, nowElapsedNS: bufferNow)
            deliveredSampleIDs.insert(sample.sampleID)
        }
        for ema in emaSamples {
            try buffers.appendEMA(ema, nowElapsedNS: bufferNow)
            lastEMABySeries[ema.seriesID] = ema
        }
        buffers.prune(nowElapsedNS: bufferNow)
        snapshotGeneration = receipt.snapshotGeneration
        processedRequests[batch.requestID] = ProcessedRequest(
            fingerprint: Self.fingerprint(for: batch),
            receipt: receipt
        )
        return receipt
    }

    public func advance(to timestamp: Timestamp, lease: PersistenceLease) async throws -> ProcessingReceipt {
        _ = timestamp
        _ = lease
        throw Self.failure(
            code: .processingValidate,
            operation: "advance",
            underlyingCode: "not_implemented"
        )
    }

    public func markGap(_ gap: Gap, lease: PersistenceLease) async throws -> ProcessingReceipt {
        _ = gap
        _ = lease
        throw Self.failure(
            code: .processingValidate,
            operation: "markGap",
            underlyingCode: "not_implemented"
        )
    }

    public func snapshot(at timestamp: Timestamp) async -> Snapshot {
        Snapshot(
            asOf: timestamp,
            values: [],
            gapIDs: [],
            cpuPeriodMS: cpuPeriodMS,
            generation: snapshotGeneration
        )
    }

    public func realtime(_ request: HistoryRequest) async -> HistoryResult {
        let now = request.asOfElapsedNS
        var points: [HistoryPoint] = []
        for seriesID in request.seriesIDs {
            for ema in buffers.emaSamples(for: seriesID, nowElapsedNS: now) {
                points.append(
                    HistoryPoint(
                        seriesID: seriesID,
                        segment: ema.segment,
                        elapsedNS: ema.timestamp.elapsedNS,
                        wallUnixNS: ema.timestamp.wallUnixNS,
                        valueC: ema.valueC,
                        minC: nil,
                        maxC: nil,
                        count: 1
                    )
                )
            }
        }
        return HistoryResult(
            layer: .ema,
            points: points,
            gaps: [],
            availableFromElapsedNS: now - configuration.retentionSeconds.ema * 1_000_000_000,
            persistedThroughElapsedNS: nil
        )
    }

    func rawSamples(for seriesID: SeriesID, nowElapsedNS: Int64) -> [Sample] {
        buffers.rawSamples(for: seriesID, nowElapsedNS: nowElapsedNS)
    }

    func emaSamples(for seriesID: SeriesID, nowElapsedNS: Int64) -> [EMAValue] {
        buffers.emaSamples(for: seriesID, nowElapsedNS: nowElapsedNS)
    }

    func activeSeriesCount() -> Int {
        buffers.activeSeriesCount
    }

    private func computeEMA(for sample: Sample, kind: SensorKind) throws -> EMAValue {
        let previous = lastEMABySeries[sample.seriesID]
        do {
            return try emaProcessor.nextEMA(raw: sample, previous: previous, kind: kind)
        } catch EMAError.nonPositiveDeltaTime {
            throw Self.failure(
                code: .processingEMA,
                operation: "accept",
                underlyingCode: "non_positive_dt"
            )
        }
    }

    private func validateLease(_ lease: PersistenceLease, for batch: ReadBatch) throws {
        guard case let .request(requestID) = lease.owner, requestID == batch.requestID else {
            throw Self.failure(
                code: .databaseIntegrity,
                operation: "accept",
                underlyingCode: "invalid_lease_owner"
            )
        }
        guard lease.generation == batch.generation else {
            throw Self.failure(
                code: .databaseIntegrity,
                operation: "accept",
                underlyingCode: "invalid_lease_generation"
            )
        }
    }

    private func validateReceipt(_ receipt: ProcessingReceipt, for batch: PersistenceBatch) throws {
        guard receipt.batchID == batch.batchID else {
            throw Self.failure(
                code: .databaseIntegrity,
                operation: "accept",
                underlyingCode: "receipt_batch_mismatch"
            )
        }
        let expectedRecords = batch.raw.count + batch.ema.count + batch.buckets.count + batch.trends.count + batch.gaps.count
        guard receipt.acceptedRecords == expectedRecords else {
            throw Self.failure(
                code: .databaseIntegrity,
                operation: "accept",
                underlyingCode: "receipt_record_mismatch"
            )
        }
    }

    private static func makeSampleID(sessionID: SessionID, sequence: Int64) -> String {
        "\(sessionID.rawValue):\(sequence)"
    }

    private static func fingerprint(for batch: ReadBatch) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(batch) else {
            return batch.requestID.rawValue
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func failure(
        code: MonitorErrorCode,
        operation: String,
        underlyingCode: String
    ) -> MonitorFailure {
        MonitorFailure(
            code: code,
            severity: .fatal,
            component: "MonitorEngine",
            operation: operation,
            retryCount: 0,
            sourceID: nil,
            underlyingCode: underlyingCode
        )
    }
}

private extension ReadBatch {
    func requestedPeriodMS(from reading: Reading) -> Int {
        max(1, Int((reading.finished.elapsedNS - reading.started.elapsedNS) / 1_000_000))
    }
}
