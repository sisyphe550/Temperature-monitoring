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
    private var sourceToSeries: [SourceID: SeriesDefinition]
    private var maximumDefinitions: [SeriesDefinition]
    private let emaProcessor: EMAProcessor
    private let cpuMaxDerivation: CPUMaxDerivation
    private let trendCalculator: TrendCalculator
    private var aggregation: AggregationEngine
    private var buffers: RingBufferStore
    private var seriesDefinitions: [SeriesID: SeriesDefinition]
    private var seriesState: [SeriesID: SeriesState]
    private var lastEMABySeries: [SeriesID: EMAValue] = [:]
    private var lastSuccessfulAtBySeries: [SeriesID: Timestamp] = [:]
    private var lastFailureBySeries: [SeriesID: MonitorFailure] = [:]
    private var openGapBySeries: [SeriesID: GapID] = [:]
    private var openGapStartedElapsedNSBySeries: [SeriesID: Int64] = [:]
    private var activeGapIDs: Set<GapID> = []
    private var nextLifecycleOrdinal: Int64 = 1
    private var qualifiedSources: [QualifiedSource]
    private var sessionStartedAt: Timestamp
    private var initialMetadataCommitted = false
    private var initialSegmentReason: SegmentReason = .sessionStart
    private var acceptedGeneration: UInt64 = 0
    private var nextSampleSequence: Int64 = 1
    private var deliveredSampleIDs: Set<String> = []
    private var processedRequests: [RequestID: ProcessedRequest] = [:]
    private var snapshotGeneration: UInt64 = 0
    private var cpuPeriodMS: Int
    // An actor is reentrant across commit(). Serialize state-changing events
    // while allowing snapshots and in-flight IO registration to proceed.
    private var mutationInProgress = false
    private var mutationWaiters: [CheckedContinuation<Void, Never>] = []

    public init(
        clock: MonitorClock,
        commit: PersistenceCommitCapability,
        session: SessionMetadata,
        configuration: RuntimeConfiguration,
        definitions: [SeriesDefinition],
        cpuPeriodMS: Int,
        qualifiedSources: [QualifiedSource] = [],
        sessionStartedAt: Timestamp? = nil
    ) {
        self.clock = clock
        self.commit = commit
        sessionID = session.sessionID
        self.configuration = configuration
        self.qualifiedSources = qualifiedSources
        self.sessionStartedAt = sessionStartedAt ?? clock.now()
        sourceToSeries = Dictionary(
            uniqueKeysWithValues: definitions
                .filter { $0.formula == .identity }
                .flatMap { definition in
                    definition.memberSourceIDs.map { ($0, definition) }
                }
        )
        maximumDefinitions = definitions.filter { $0.formula == .maximum }
        emaProcessor = EMAProcessor(tauSeconds: configuration.emaTauSeconds)
        cpuMaxDerivation = CPUMaxDerivation(maxBatchSpanMS: configuration.cpuMaxBatchSpanMS)
        trendCalculator = TrendCalculator(configuration: configuration)
        aggregation = AggregationEngine()
        seriesDefinitions = Dictionary(uniqueKeysWithValues: definitions.map { ($0.seriesID, $0) })
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
        await beginMutation()
        defer { endMutation() }
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
        var stagedSeriesState = seriesState
        var stagedSequence = nextSampleSequence
        var stagedSuccessfulAt = lastSuccessfulAtBySeries
        var stagedFailures = lastFailureBySeries

        let now = clock.now()
        var rawSamples: [Sample] = []
        var emaSamples: [EMAValue] = []
        var batchMemberSamples: [SourceID: Sample] = [:]
        for reading in batch.readings {
            switch reading.outcome {
            case let .failure(failure):
                if let definition = sourceToSeries[reading.sourceID] {
                    stagedFailures[definition.seriesID] = failure
                }
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
                guard let definition = sourceToSeries[reading.sourceID], definition.formula == .identity else {
                    throw Self.failure(
                        code: .processingValidate,
                        operation: "accept",
                        underlyingCode: "unknown_source"
                    )
                }
                let elapsedNS = reading.finished.elapsedNS
                var state = stagedSeriesState[definition.seriesID] ?? SeriesState(segment: 1, lastElapsedNS: Int64.min)
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
                let sampleID = Self.makeSampleID(sessionID: sessionID, sequence: stagedSequence)
                stagedSequence += 1
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
                    periodMS: batch.requestedPeriodMS,
                    valueC: valueC,
                    freshness: freshness,
                    sourceWallUnixNS: sourceWallUnixNS,
                    memberSampleIDs: []
                )
                rawSamples.append(sample)
                batchMemberSamples[reading.sourceID] = sample
                let ema = try computeEMA(for: sample, kind: definition.kind)
                emaSamples.append(ema)
                stagedSuccessfulAt[definition.seriesID] = reading.finished
                stagedFailures.removeValue(forKey: definition.seriesID)
                state.lastElapsedNS = elapsedNS
                stagedSeriesState[definition.seriesID] = state
            }
        }

        for maximumDefinition in maximumDefinitions {
            let segment = stagedSeriesState[maximumDefinition.seriesID]?.segment ?? 1
            if let derived = cpuMaxDerivation.derive(
                definition: maximumDefinition,
                memberSamples: batchMemberSamples,
                readings: batch.readings,
                sessionID: sessionID,
                sampleSequence: &stagedSequence,
                segment: segment,
                periodMS: batch.requestedPeriodMS
            ) {
                rawSamples.append(derived)
                let ema = try computeEMA(for: derived, kind: maximumDefinition.kind)
                emaSamples.append(ema)
                var state = stagedSeriesState[maximumDefinition.seriesID] ?? SeriesState(segment: segment, lastElapsedNS: Int64.min)
                state.lastElapsedNS = derived.timestamp.elapsedNS
                stagedSeriesState[maximumDefinition.seriesID] = state
                stagedSuccessfulAt[maximumDefinition.seriesID] = derived.timestamp
                stagedFailures.removeValue(forKey: maximumDefinition.seriesID)
            } else if !Set(maximumDefinition.memberSourceIDs).isDisjoint(with: batch.readings.map(\.sourceID)) {
                let failure = batch.readings.compactMap { reading -> MonitorFailure? in
                    guard maximumDefinition.memberSourceIDs.contains(reading.sourceID), case let .failure(failure) = reading.outcome else { return nil }
                    return failure
                }.first ?? Self.failure(code: .sensorRead, operation: "cpuMaximum", underlyingCode: "incomplete_cpu_batch")
                stagedFailures[maximumDefinition.seriesID] = failure
            }
        }

        let persistenceBatch = makePersistenceBatch(
            raw: rawSamples,
            ema: emaSamples,
            buckets: [],
            trends: [],
            gaps: []
        )

        let receipt = try await commit.commit(persistenceBatch, using: lease)
        try validateReceipt(receipt, for: persistenceBatch)
        acceptedGeneration = max(acceptedGeneration, batch.generation)
        nextSampleSequence = stagedSequence
        // Definitions may have been extended during the awaited commit.
        for sample in rawSamples { seriesState[sample.seriesID] = stagedSeriesState[sample.seriesID] }
        lastSuccessfulAtBySeries = stagedSuccessfulAt
        lastFailureBySeries = stagedFailures
        markInitialMetadataCommittedIfNeeded(for: persistenceBatch)

        let bufferNow = max(now.elapsedNS, rawSamples.map(\.timestamp.elapsedNS).max() ?? now.elapsedNS)
        for sample in rawSamples {
            aggregation.ingest(sample)
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

    public func setCPUPeriod(milliseconds: Int) {
        cpuPeriodMS = milliseconds
    }

    public func trackedSeriesIDs() -> [SeriesID] {
        Array(seriesDefinitions.keys)
    }

    public func replaceDefinitions(_ definitions: [SeriesDefinition], qualifiedSources: [QualifiedSource] = []) async {
        await beginMutation()
        defer { endMutation() }
        seriesDefinitions = Dictionary(uniqueKeysWithValues: definitions.map { ($0.seriesID, $0) })
        sourceToSeries = Dictionary(uniqueKeysWithValues: definitions.filter { $0.formula == .identity }
            .flatMap { definition in definition.memberSourceIDs.map { ($0, definition) } })
        maximumDefinitions = definitions.filter { $0.formula == .maximum }
        let ids = Set(definitions.map(\.seriesID))
        buffers.retainSeries(ids)
        lastEMABySeries = lastEMABySeries.filter { ids.contains($0.key) }
        lastSuccessfulAtBySeries = lastSuccessfulAtBySeries.filter { ids.contains($0.key) }
        lastFailureBySeries = lastFailureBySeries.filter { ids.contains($0.key) }
        for definition in definitions where seriesState[definition.seriesID] == nil {
            seriesState[definition.seriesID] = SeriesState(segment: 1, lastElapsedNS: Int64.min)
            try? buffers.registerSeries(definition.seriesID)
        }
        if !qualifiedSources.isEmpty, self.qualifiedSources != qualifiedSources {
            self.qualifiedSources = qualifiedSources
            sessionStartedAt = clock.now()
            initialMetadataCommitted = false
            initialSegmentReason = .sourceChange
        }
    }

    public func openSleepGaps(at timestamp: Timestamp) throws -> [Gap] {
        try trackedSeriesIDs().compactMap { seriesID in
            guard openGapBySeries[seriesID] == nil else {
                return nil
            }
            let gapID = try makeLifecycleGapID()
            return Gap(
                gapID: gapID,
                seriesID: seriesID,
                startedElapsedNS: timestamp.elapsedNS,
                endedElapsedNS: nil,
                reason: .sleep
            )
        }
    }

    public func closeOpenGapsForWake(at timestamp: Timestamp) throws -> (gaps: [Gap], segments: [Segment]) {
        var gaps: [Gap] = []
        var segments: [Segment] = []
        for seriesID in openGapBySeries.keys {
            guard let gapID = openGapBySeries[seriesID] else {
                continue
            }
            let startedElapsedNS = openGapStartedElapsedNSBySeries[seriesID] ?? timestamp.elapsedNS
            gaps.append(
                Gap(
                    gapID: gapID,
                    seriesID: seriesID,
                    startedElapsedNS: startedElapsedNS,
                    endedElapsedNS: timestamp.elapsedNS,
                    reason: .sleep
                )
            )
            let segmentNumber = (seriesState[seriesID]?.segment ?? 1) + 1
            segments.append(
                Segment(
                    seriesID: seriesID,
                    number: segmentNumber,
                    started: timestamp,
                    reason: .wake
                )
            )
        }
        return (gaps, segments)
    }

    public func commitLifecycleTransition(
        gaps: [Gap],
        segments: [Segment],
        lease: PersistenceLease
    ) async throws -> ProcessingReceipt {
        await beginMutation()
        defer { endMutation() }
        try validateLifecycleLease(lease)
        let persistenceBatch = makePersistenceBatch(
            raw: [],
            ema: [],
            buckets: [],
            trends: [],
            gaps: gaps,
            segments: segments
        )
        let receipt = try await commit.commit(persistenceBatch, using: lease)
        try validateReceipt(receipt, for: persistenceBatch)
        markInitialMetadataCommittedIfNeeded(for: persistenceBatch)

        for gap in gaps {
            activeGapIDs.insert(gap.gapID)
            if gap.endedElapsedNS == nil {
                openGapBySeries[gap.seriesID] = gap.gapID
                openGapStartedElapsedNSBySeries[gap.seriesID] = gap.startedElapsedNS
            } else {
                openGapBySeries.removeValue(forKey: gap.seriesID)
                openGapStartedElapsedNSBySeries.removeValue(forKey: gap.seriesID)
                activeGapIDs.remove(gap.gapID)
            }
        }
        for segment in segments {
            seriesState[segment.seriesID] = SeriesState(segment: segment.number, lastElapsedNS: segment.started.elapsedNS)
            lastEMABySeries.removeValue(forKey: segment.seriesID)
        }
        snapshotGeneration = receipt.snapshotGeneration
        return receipt
    }

    public func registerInFlightReading(startElapsedNS: Int64) {
        aggregation.beginInFlight(startElapsedNS: [startElapsedNS])
    }

    public func unregisterInFlightReading(startElapsedNS: Int64) {
        aggregation.endInFlight(startElapsedNS: [startElapsedNS])
    }

    public func safeWatermarkElapsedNS(at timestamp: Timestamp) -> Int64 {
        SafeWatermark.maximumClosureElapsedNS(
            nowElapsedNS: timestamp.elapsedNS,
            inFlightStartElapsedNS: aggregation.activeInFlightStarts()
        )
    }

    public func advance(to timestamp: Timestamp, lease: PersistenceLease) async throws -> ProcessingReceipt {
        await beginMutation()
        defer { endMutation() }
        try validateWatermarkLease(lease)
        let safeWatermark = safeWatermarkElapsedNS(at: timestamp)
        guard timestamp.elapsedNS <= safeWatermark else {
            throw Self.failure(
                code: .processingValidate,
                operation: "advance",
                underlyingCode: "unsafe_watermark"
            )
        }
        var stagedAggregation = aggregation
        let buckets = stagedAggregation.advance(to: timestamp.elapsedNS)
        let trends = computeTrends(at: timestamp)
        let persistenceBatch = makePersistenceBatch(
            raw: [],
            ema: [],
            buckets: buckets,
            trends: trends,
            gaps: []
        )
        let receipt = try await commit.commit(persistenceBatch, using: lease)
        try validateReceipt(receipt, for: persistenceBatch)
        aggregation.commitWindows(from: stagedAggregation)
        markInitialMetadataCommittedIfNeeded(for: persistenceBatch)
        snapshotGeneration = receipt.snapshotGeneration
        return receipt
    }

    public func markGap(_ gap: Gap, lease: PersistenceLease) async throws -> ProcessingReceipt {
        await beginMutation()
        defer { endMutation() }
        try validateGapLease(lease, for: gap)

        if gap.endedElapsedNS == nil, openGapBySeries[gap.seriesID] != nil {
            throw Self.failure(
                code: .processingValidate,
                operation: "markGap",
                underlyingCode: "duplicate_open_gap"
            )
        }

        let persistenceBatch = makePersistenceBatch(
            raw: [],
            ema: [],
            buckets: [],
            trends: [],
            gaps: [gap]
        )
        let receipt = try await commit.commit(persistenceBatch, using: lease)
        try validateReceipt(receipt, for: persistenceBatch)
        markInitialMetadataCommittedIfNeeded(for: persistenceBatch)

        activeGapIDs.insert(gap.gapID)
        if gap.endedElapsedNS == nil {
            openGapBySeries[gap.seriesID] = gap.gapID
            openGapStartedElapsedNSBySeries[gap.seriesID] = gap.startedElapsedNS
        } else {
            openGapBySeries.removeValue(forKey: gap.seriesID)
            openGapStartedElapsedNSBySeries.removeValue(forKey: gap.seriesID)
            beginSegment(for: gap.seriesID, afterElapsedNS: gap.endedElapsedNS ?? timestampFromGap(gap))
        }
        snapshotGeneration = receipt.snapshotGeneration
        return receipt
    }

    public func snapshot(at timestamp: Timestamp) async -> Snapshot {
        let values = seriesDefinitions.values
            .sorted { $0.displayName < $1.displayName }
            .map { definition -> LatestValue in
                let segment = seriesState[definition.seriesID]?.segment ?? 1
                if let ema = lastEMABySeries[definition.seriesID], ema.segment == segment {
                    return LatestValue(
                        definition: definition,
                        state: .available(
                            ema: ema,
                            lastSuccessfulAt: lastSuccessfulAtBySeries[definition.seriesID] ?? ema.timestamp,
                            lastFailure: lastFailureBySeries[definition.seriesID]
                        )
                    )
                }
                if let failure = lastFailureBySeries[definition.seriesID] {
                    return LatestValue(definition: definition, state: .unavailable(capability: .failed,
                        reason: "\(failure.code.rawValue): \(failure.underlyingCode ?? failure.operation)"))
                }
                return LatestValue(definition: definition, state: .loading)
            }
        return Snapshot(
            asOf: timestamp,
            values: values,
            gapIDs: Array(activeGapIDs),
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

    private func beginMutation() async {
        if mutationInProgress {
            await withCheckedContinuation { mutationWaiters.append($0) }
        } else {
            mutationInProgress = true
        }
    }

    private func endMutation() {
        if mutationWaiters.isEmpty {
            mutationInProgress = false
        } else {
            mutationWaiters.removeFirst().resume()
        }
    }

    private func makePersistenceBatch(
        raw: [Sample],
        ema: [EMAValue],
        buckets: [Bucket],
        trends: [TrendValue],
        gaps: [Gap],
        segments: [Segment] = []
    ) -> PersistenceBatch {
        let metadata = initialMetadataPayload()
        return PersistenceBatch(
            batchID: BatchID(UUID()),
            sources: metadata.sources,
            definitions: metadata.definitions,
            segments: metadata.segments + segments,
            raw: raw,
            ema: ema,
            buckets: buckets,
            trends: trends,
            gaps: gaps
        )
    }

    private func makeLifecycleGapID() throws -> GapID {
        let ordinal = nextLifecycleOrdinal
        nextLifecycleOrdinal += 1
        let raw = String(format: "00000000-0000-4000-8000-%012d", ordinal)
        return try GapID(validating: raw)
    }

    private func validateLifecycleLease(_ lease: PersistenceLease) throws {
        guard case .gap = lease.owner else {
            throw Self.failure(
                code: .databaseIntegrity,
                operation: "commitLifecycleTransition",
                underlyingCode: "invalid_lease_owner"
            )
        }
    }

    private func initialMetadataPayload() -> (
        sources: [QualifiedSource],
        definitions: [SeriesDefinition],
        segments: [Segment]
    ) {
        guard !initialMetadataCommitted, !qualifiedSources.isEmpty else {
            return ([], [], [])
        }
        return (
            qualifiedSources,
            Array(seriesDefinitions.values),
            seriesDefinitions.values.map { definition in
                Segment(
                    seriesID: definition.seriesID,
                    number: 1,
                    started: sessionStartedAt,
                    reason: initialSegmentReason
                )
            }
        )
    }

    private func markInitialMetadataCommittedIfNeeded(for batch: PersistenceBatch) {
        if !initialMetadataCommitted, !batch.sources.isEmpty {
            initialMetadataCommitted = true
        }
    }

    private func computeTrends(at timestamp: Timestamp) -> [TrendValue] {
        seriesDefinitions.values.map { definition in
            let segment = seriesState[definition.seriesID]?.segment ?? 1
            let emaSamples = buffers.emaSamples(
                for: definition.seriesID,
                nowElapsedNS: timestamp.elapsedNS
            )
            return trendCalculator.compute(
                seriesID: definition.seriesID,
                segment: segment,
                kind: definition.kind,
                emaSamples: emaSamples,
                at: timestamp
            )
        }
    }

    private func beginSegment(for seriesID: SeriesID, afterElapsedNS: Int64) {
        var state = seriesState[seriesID] ?? SeriesState(segment: 1, lastElapsedNS: Int64.min)
        state.segment += 1
        state.lastElapsedNS = afterElapsedNS
        seriesState[seriesID] = state
        lastEMABySeries.removeValue(forKey: seriesID)
    }

    private func timestampFromGap(_ gap: Gap) -> Int64 {
        gap.endedElapsedNS ?? gap.startedElapsedNS
    }

    private func computeEMA(for sample: Sample, kind: SensorKind) throws -> EMAValue {
        let stored = lastEMABySeries[sample.seriesID]
        let previous = stored?.segment == sample.segment ? stored : nil
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

    private func validateWatermarkLease(_ lease: PersistenceLease) throws {
        guard case .watermark = lease.owner else {
            throw Self.failure(
                code: .databaseIntegrity,
                operation: "advance",
                underlyingCode: "invalid_lease_owner"
            )
        }
    }

    private func validateGapLease(_ lease: PersistenceLease, for gap: Gap) throws {
        guard case let .gap(gapID) = lease.owner, gapID == gap.gapID else {
            throw Self.failure(
                code: .databaseIntegrity,
                operation: "markGap",
                underlyingCode: "invalid_lease_owner"
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
        let expectedRecords = PersistenceBatchMetrics.logicalRecordCount(batch)
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
