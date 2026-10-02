import Foundation
import CryptoKit

public actor MonitorEngine: ProcessingEngine {
    private struct ProcessedRequest: Equatable {
        let fingerprint: String
        let receipt: ProcessingReceipt
        let lease: PersistenceLease
        let finishedElapsedNS: Int64
    }

    private struct SeriesState {
        var segment: Int64
        var lastElapsedNS: Int64
        var lastPeriodMS: Int? = nil
        var minimumElapsedNS: Int64 = 0
    }

    private struct GapChanges {
        var open: [SeriesID: GapID]
        var starts: [SeriesID: Int64]
        var active: Set<GapID>
        var history: [GapID: Gap]
        var writes: [GapID: Gap] = [:]
        var segments: [Segment] = []
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
    private var archivedEMABySeries: [SeriesID: [EMAValue]] = [:]
    private var capabilityValues: [LatestValue]
    private var seriesDefinitions: [SeriesID: SeriesDefinition]
    private var seriesState: [SeriesID: SeriesState]
    private var lastEMABySeries: [SeriesID: EMAValue] = [:]
    private var lastSuccessfulAtBySeries: [SeriesID: Timestamp] = [:]
    private var lastFailureBySeries: [SeriesID: MonitorFailure] = [:]
    private var openGapBySeries: [SeriesID: GapID] = [:]
    private var openGapStartedElapsedNSBySeries: [SeriesID: Int64] = [:]
    private var activeGapIDs: Set<GapID> = []
    private var historyGaps: [GapID: Gap] = [:]
    private var optionalAvailabilityFailures: [SensorKind: MonitorFailure] = [:]
    private var qualifiedSources: [QualifiedSource]
    private var sessionStartedAt: Timestamp
    private var initialMetadataCommitted = false
    private var initialSegmentReason: SegmentReason = .sessionStart
    private var acceptedGeneration: UInt64 = 0
    private var nextSampleSequence: Int64 = 1
    private var processedRequests: [RequestID: ProcessedRequest] = [:]
    private var processedRequestOrder: [RequestID] = []
    private var processedRequestHead = 0
    private var expiredRequestThroughElapsedNS: Int64 = -1
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
        sessionStartedAt: Timestamp? = nil,
        capabilityValues: [LatestValue] = []
    ) {
        self.clock = clock
        self.capabilityValues = capabilityValues
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
        pruneReplayCache(nowElapsedNS: clock.now().elapsedNS)
        if let processed = processedRequests[batch.requestID] {
            let fingerprint = Self.fingerprint(for: batch)
            guard processed.fingerprint == fingerprint else {
                throw Self.failure(
                    code: .databaseIntegrity,
                    operation: "accept",
                    underlyingCode: "request_content_mismatch"
                )
            }
            guard processed.lease == lease else {
                throw Self.failure(code: .databaseIntegrity, operation: "accept", underlyingCode: "lease_replay_mismatch")
            }
            return processed.receipt
        }

        if let finished = batch.readings.map(\.finished.elapsedNS).max(), finished <= expiredRequestThroughElapsedNS {
            throw Self.failure(code: .processingValidate, operation: "accept", underlyingCode: "expired_request")
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
        var stagedEMA = lastEMABySeries
        var stagedGaps = currentGapChanges()

        let now = clock.now()
        var rawSamples: [Sample] = []
        var emaSamples: [EMAValue] = []
        var batchMemberSamples: [SourceID: Sample] = [:]
        for reading in batch.readings {
            guard let definition = sourceToSeries[reading.sourceID], definition.formula == .identity else {
                throw Self.failure(code: .processingValidate, operation: "accept", underlyingCode: "unknown_source")
            }
            switch reading.outcome {
            case let .failure(failure):
                let state = stagedSeriesState[definition.seriesID]
                guard reading.finished.elapsedNS >= (state?.lastElapsedNS ?? Int64.min),
                      reading.finished.elapsedNS >= (state?.minimumElapsedNS ?? 0) else { continue }
                stagedFailures[definition.seriesID] = failure
                stageFailureGap(seriesID: definition.seriesID, atElapsedNS: reading.started.elapsedNS,
                    reason: failure.code == .sensorTimeout ? .timeout : .readFailure, changes: &stagedGaps)
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
                let elapsedNS = reading.finished.elapsedNS
                var state = stagedSeriesState[definition.seriesID] ?? SeriesState(segment: 1, lastElapsedNS: Int64.min)
                if elapsedNS < state.lastElapsedNS || elapsedNS < state.minimumElapsedNS {
                    continue
                }
                if elapsedNS == state.lastElapsedNS {
                    throw Self.failure(
                        code: .processingValidate,
                        operation: "accept",
                        underlyingCode: "non_monotonic_elapsed"
                    )
                }
                try stageRecoveryGap(seriesID: definition.seriesID, at: reading.finished,
                    currentPeriodMS: batch.requestedPeriodMS, state: &state, changes: &stagedGaps)
                let sampleID = Self.makeSampleID(sessionID: sessionID, sequence: stagedSequence)
                stagedSequence += 1
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
                let ema = try computeEMA(for: sample, kind: definition.kind, previous: stagedEMA[sample.seriesID])
                emaSamples.append(ema)
                stagedEMA[sample.seriesID] = ema
                stagedSuccessfulAt[definition.seriesID] = reading.finished
                stagedFailures.removeValue(forKey: definition.seriesID)
                state.lastElapsedNS = elapsedNS
                state.lastPeriodMS = batch.requestedPeriodMS
                stagedSeriesState[definition.seriesID] = state
            }
        }

        for definition in maximumDefinitions {
            let memberReadings = batch.readings.filter { definition.memberSourceIDs.contains($0.sourceID) }
            guard let latest = memberReadings.map(\.finished).max(by: { $0.elapsedNS < $1.elapsedNS }) else { continue }
            var state = stagedSeriesState[definition.seriesID] ?? SeriesState(segment: 1, lastElapsedNS: Int64.min)
            guard latest.elapsedNS >= state.lastElapsedNS, latest.elapsedNS >= state.minimumElapsedNS else { continue }
            if cpuMaxDerivation.canDerive(definition: definition, memberSamples: batchMemberSamples, readings: batch.readings) {
                guard latest.elapsedNS != state.lastElapsedNS else {
                    throw Self.failure(code: .processingValidate, operation: "accept", underlyingCode: "non_monotonic_elapsed")
                }
                try stageRecoveryGap(seriesID: definition.seriesID, at: latest,
                    currentPeriodMS: batch.requestedPeriodMS, state: &state, changes: &stagedGaps)
                guard let derived = cpuMaxDerivation.derive(definition: definition, memberSamples: batchMemberSamples,
                    readings: batch.readings, sessionID: sessionID, sampleSequence: &stagedSequence,
                    segment: state.segment, periodMS: batch.requestedPeriodMS) else { continue }
                rawSamples.append(derived)
                let ema = try computeEMA(for: derived, kind: definition.kind, previous: stagedEMA[definition.seriesID])
                emaSamples.append(ema)
                stagedEMA[definition.seriesID] = ema
                state.lastElapsedNS = derived.timestamp.elapsedNS
                state.lastPeriodMS = batch.requestedPeriodMS
                stagedSeriesState[definition.seriesID] = state
                stagedSuccessfulAt[definition.seriesID] = derived.timestamp
                stagedFailures.removeValue(forKey: definition.seriesID)
            } else {
                let failure = memberReadings.compactMap { reading -> MonitorFailure? in
                    if case let .failure(failure) = reading.outcome { return failure }
                    return nil
                }.first ?? Self.failure(code: .sensorRead, operation: "cpuMaximum", underlyingCode: "incomplete_cpu_batch")
                stagedFailures[definition.seriesID] = failure
                let started = memberReadings.map(\.started.elapsedNS).min() ?? latest.elapsedNS
                stageFailureGap(seriesID: definition.seriesID, atElapsedNS: started,
                    reason: failure.code == .sensorTimeout ? .timeout : .readFailure, changes: &stagedGaps)
            }
        }

        let persistenceBatch = makePersistenceBatch(
            raw: rawSamples,
            ema: emaSamples,
            buckets: [],
            trends: [],
            gaps: Array(stagedGaps.writes.values),
            segments: stagedGaps.segments
        )

        let receipt = try await commit.commit(persistenceBatch, using: lease)
        try validateReceipt(receipt, for: persistenceBatch)
        acceptedGeneration = max(acceptedGeneration, batch.generation)
        nextSampleSequence = stagedSequence
        seriesState = stagedSeriesState
        applyGapChanges(stagedGaps)
        lastSuccessfulAtBySeries = stagedSuccessfulAt
        lastFailureBySeries = stagedFailures
        markInitialMetadataCommittedIfNeeded(for: persistenceBatch)

        let bufferNow = max(now.elapsedNS, batch.readings.map(\.finished.elapsedNS).max() ?? now.elapsedNS)
        pruneHistoryGaps(nowElapsedNS: bufferNow)
        for sample in rawSamples {
            aggregation.ingest(sample)
            try buffers.appendRaw(sample, nowElapsedNS: bufferNow)
        }
        for ema in emaSamples {
            try buffers.appendEMA(ema, nowElapsedNS: bufferNow)
            lastEMABySeries[ema.seriesID] = ema
        }
        buffers.prune(nowElapsedNS: bufferNow)
        snapshotGeneration = receipt.snapshotGeneration
        pruneReplayCache(nowElapsedNS: bufferNow)
        processedRequestOrder.append(batch.requestID)
        processedRequests[batch.requestID] = ProcessedRequest(
            fingerprint: Self.fingerprint(for: batch),
            receipt: receipt,
            lease: lease,
            finishedElapsedNS: batch.readings.map(\.finished.elapsedNS).max() ?? bufferNow
        )
        return receipt
    }

    public func setOptionalAvailability(kind: SensorKind, failure: MonitorFailure?) async {
        guard kind == .ssd || kind == .battery else { return }
        if let failure {
            optionalAvailabilityFailures[kind] = failure
        } else {
            optionalAvailabilityFailures.removeValue(forKey: kind)
        }
    }

    func historyGapsFor(request: HistoryRequest) -> [Gap] {
        pruneHistoryGaps(nowElapsedNS: request.asOfElapsedNS)
        let ids = Set(request.seriesIDs)
        let lowerBound = request.asOfElapsedNS - request.range.rawValue * 1_000_000_000
        return historyGaps.values.filter { gap in
            ids.contains(gap.seriesID) && gap.startedElapsedNS <= request.asOfElapsedNS
                && (gap.endedElapsedNS == nil || gap.endedElapsedNS! > lowerBound)
        }.sorted {
            if $0.startedElapsedNS == $1.startedElapsedNS { return $0.gapID.rawValue < $1.gapID.rawValue }
            return $0.startedElapsedNS < $1.startedElapsedNS
        }
    }

    public func setCPUPeriod(milliseconds: Int) {
        cpuPeriodMS = milliseconds
    }

    public func trackedSeriesIDs() -> [SeriesID] {
        Array(seriesDefinitions.keys)
    }

    public func replaceDefinitions(_ definitions: [SeriesDefinition], qualifiedSources: [QualifiedSource] = [], capabilityValues: [LatestValue] = []) async {
        await beginMutation()
        defer { endMutation() }
        let now = clock.now().elapsedNS
        let nextIDs = Set(definitions.map(\.seriesID))
        for oldID in seriesDefinitions.keys where !nextIDs.contains(oldID) {
            let samples = buffers.emaSamples(for: oldID, nowElapsedNS: now)
            if !samples.isEmpty { archivedEMABySeries[oldID] = samples }
        }
        pruneArchivedEMA(nowElapsedNS: now)
        self.capabilityValues = capabilityValues
        seriesDefinitions = Dictionary(uniqueKeysWithValues: definitions.map { ($0.seriesID, $0) })
        sourceToSeries = Dictionary(uniqueKeysWithValues: definitions.filter { $0.formula == .identity }
            .flatMap { definition in definition.memberSourceIDs.map { ($0, definition) } })
        maximumDefinitions = definitions.filter { $0.formula == .maximum }
        let ids = Set(definitions.map(\.seriesID))
        buffers.retainSeries(ids)
        lastEMABySeries = lastEMABySeries.filter { ids.contains($0.key) }
        lastSuccessfulAtBySeries = lastSuccessfulAtBySeries.filter { ids.contains($0.key) }
        lastFailureBySeries = lastFailureBySeries.filter { ids.contains($0.key) }
        seriesState = seriesState.filter { ids.contains($0.key) || openGapBySeries[$0.key] != nil }
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

    public func closeOpenGapsForSourceChange(at timestamp: Timestamp) -> [Gap] {
        openGapBySeries.compactMap { seriesID, gapID in
            guard let gap = historyGaps[gapID] else { return nil }
            return Gap(gapID: gapID, seriesID: seriesID, startedElapsedNS: gap.startedElapsedNS,
                endedElapsedNS: max(timestamp.elapsedNS, gap.startedElapsedNS), reason: gap.reason)
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
                    reason: historyGaps[gapID]?.reason ?? .sleep
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

        var gapChanges = currentGapChanges()
        for gap in gaps { stageCommittedGap(gap, changes: &gapChanges) }
        applyGapChanges(gapChanges)
        for segment in segments {
            seriesState[segment.seriesID] = SeriesState(segment: segment.number, lastElapsedNS: Int64.min,
                minimumElapsedNS: segment.started.elapsedNS)
            lastEMABySeries.removeValue(forKey: segment.seriesID)
        }
        pruneHistoryGaps(nowElapsedNS: clock.now().elapsedNS)
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
            throw Self.failure(code: .processingValidate, operation: "markGap", underlyingCode: "duplicate_open_gap")
        }
        if let openID = openGapBySeries[gap.seriesID], openID != gap.gapID {
            throw Self.failure(code: .processingValidate, operation: "markGap", underlyingCode: "gap_id_mismatch")
        }
        var segments: [Segment] = []
        if let ended = gap.endedElapsedNS, historyGaps[gap.gapID]?.endedElapsedNS == nil {
            let now = clock.now()
            let started = Timestamp(elapsedNS: ended, wallUnixNS: now.wallUnixNS + (ended - now.elapsedNS))
            segments = [Segment(seriesID: gap.seriesID, number: (seriesState[gap.seriesID]?.segment ?? 1) + 1,
                started: started, reason: .gap)]
        }
        let persistenceBatch = makePersistenceBatch(raw: [], ema: [], buckets: [], trends: [], gaps: [gap], segments: segments)
        let receipt = try await commit.commit(persistenceBatch, using: lease)
        try validateReceipt(receipt, for: persistenceBatch)
        markInitialMetadataCommittedIfNeeded(for: persistenceBatch)
        var gapChanges = currentGapChanges()
        stageCommittedGap(gap, changes: &gapChanges)
        applyGapChanges(gapChanges)
        for segment in segments {
            seriesState[segment.seriesID] = SeriesState(segment: segment.number, lastElapsedNS: Int64.min,
                minimumElapsedNS: segment.started.elapsedNS)
            lastEMABySeries.removeValue(forKey: segment.seriesID)
        }
        pruneHistoryGaps(nowElapsedNS: clock.now().elapsedNS)
        snapshotGeneration = receipt.snapshotGeneration
        return receipt
    }

    public func snapshot(at timestamp: Timestamp) async -> Snapshot {
        let values = seriesDefinitions.values
            .sorted { $0.displayName < $1.displayName }
            .map { definition -> LatestValue in
                let segment = seriesState[definition.seriesID]?.segment ?? 1
                if let failure = optionalAvailabilityFailures[definition.kind] {
                    return LatestValue(definition: definition, state: .unavailable(capability: .failed,
                        reason: "\(failure.code.rawValue): \(failure.underlyingCode ?? failure.operation)"))
                }
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
            values: values + capabilityValues,
            gapIDs: Array(activeGapIDs),
            cpuPeriodMS: cpuPeriodMS,
            generation: snapshotGeneration
        )
    }

    public func realtime(_ request: HistoryRequest) async -> HistoryResult {
        let now = request.asOfElapsedNS
        pruneArchivedEMA(nowElapsedNS: now)
        var points: [HistoryPoint] = []
        for seriesID in request.seriesIDs {
            let samples = buffers.emaSamples(for: seriesID, nowElapsedNS: now) + (archivedEMABySeries[seriesID] ?? [])
            for ema in samples where ema.timestamp.elapsedNS <= now {
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
            gaps: historyGapsFor(request: request),
            availableFromElapsedNS: points.map(\.elapsedNS).min(),
            persistedThroughElapsedNS: nil
        )
    }

    private func pruneArchivedEMA(nowElapsedNS: Int64) {
        let cutoff = nowElapsedNS - configuration.retentionSeconds.ema * 1_000_000_000
        archivedEMABySeries = archivedEMABySeries.compactMapValues { samples in
            let retained = samples.filter { $0.timestamp.elapsedNS > cutoff }
            return retained.isEmpty ? nil : retained
        }
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
        GapID(UUID())
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

    private func currentGapChanges() -> GapChanges {
        GapChanges(open: openGapBySeries, starts: openGapStartedElapsedNSBySeries,
            active: activeGapIDs, history: historyGaps)
    }

    private func applyGapChanges(_ changes: GapChanges) {
        openGapBySeries = changes.open
        openGapStartedElapsedNSBySeries = changes.starts
        activeGapIDs = changes.active
        historyGaps = changes.history
    }

    private func stageCommittedGap(_ gap: Gap, changes: inout GapChanges) {
        changes.history[gap.gapID] = gap
        if gap.endedElapsedNS == nil {
            changes.open[gap.seriesID] = gap.gapID
            changes.starts[gap.seriesID] = gap.startedElapsedNS
            changes.active.insert(gap.gapID)
        } else {
            if changes.open[gap.seriesID] == gap.gapID {
                changes.open.removeValue(forKey: gap.seriesID)
                changes.starts.removeValue(forKey: gap.seriesID)
            }
            changes.active.remove(gap.gapID)
        }
    }

    private func stageFailureGap(seriesID: SeriesID, atElapsedNS: Int64, reason: GapReason, changes: inout GapChanges) {
        guard changes.open[seriesID] == nil else { return }
        let gap = Gap(gapID: GapID(UUID()), seriesID: seriesID, startedElapsedNS: atElapsedNS,
            endedElapsedNS: nil, reason: reason)
        stageCommittedGap(gap, changes: &changes)
        changes.writes[gap.gapID] = gap
    }

    private func stageRecoveryGap(seriesID: SeriesID, at timestamp: Timestamp, currentPeriodMS: Int,
        state: inout SeriesState, changes: inout GapChanges) throws {
        let gap: Gap
        let reason: SegmentReason
        if let gapID = changes.open[seriesID] {
            let start = changes.starts[seriesID] ?? timestamp.elapsedNS
            guard timestamp.elapsedNS >= start else {
                throw Self.failure(code: .processingValidate, operation: "accept", underlyingCode: "recovery_before_gap")
            }
            gap = Gap(gapID: gapID, seriesID: seriesID, startedElapsedNS: start,
                endedElapsedNS: timestamp.elapsedNS, reason: changes.history[gapID]?.reason ?? .readFailure)
            reason = .recovery
        } else {
            guard state.lastElapsedNS != Int64.min, let previousPeriodMS = state.lastPeriodMS,
                  GapDetector.isTimeoutGap(deltaElapsedNS: timestamp.elapsedNS - state.lastElapsedNS,
                    previousPeriodMS: previousPeriodMS, currentPeriodMS: currentPeriodMS,
                    gapPeriodMultiplier: configuration.gapPeriodMultiplier, gapFloorMS: configuration.gapFloorMS) else { return }
            gap = Gap(gapID: GapID(UUID()), seriesID: seriesID, startedElapsedNS: state.lastElapsedNS,
                endedElapsedNS: timestamp.elapsedNS, reason: .timeout)
            reason = .gap
        }
        stageCommittedGap(gap, changes: &changes)
        changes.writes[gap.gapID] = gap
        state.segment += 1
        state.minimumElapsedNS = timestamp.elapsedNS
        changes.segments.append(Segment(seriesID: seriesID, number: state.segment, started: timestamp, reason: reason))
    }

    private func pruneHistoryGaps(nowElapsedNS: Int64) {
        let cutoff = nowElapsedNS - configuration.retentionSeconds.ema * 1_000_000_000
        historyGaps = historyGaps.filter { _, gap in
            gap.endedElapsedNS == nil || gap.endedElapsedNS! > cutoff
        }
    }

    private func computeEMA(for sample: Sample, kind: SensorKind, previous stored: EMAValue?) throws -> EMAValue {
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

    private func pruneReplayCache(nowElapsedNS: Int64) {
        let cutoff = nowElapsedNS - configuration.retentionSeconds.raw * 1_000_000_000
        while processedRequestHead < processedRequestOrder.count {
            let id = processedRequestOrder[processedRequestHead]
            guard let entry = processedRequests[id] else { processedRequestHead += 1; continue }
            guard entry.finishedElapsedNS <= cutoff || processedRequests.count >= configuration.writerMaxRecords else { break }
            expiredRequestThroughElapsedNS = max(expiredRequestThroughElapsedNS, entry.finishedElapsedNS)
            processedRequests.removeValue(forKey: id)
            processedRequestHead += 1
        }
        if processedRequestHead > 1024, processedRequestHead * 2 >= processedRequestOrder.count {
            processedRequestOrder.removeFirst(processedRequestHead)
            processedRequestHead = 0
        }
    }

    func replayCacheCountForTesting() -> Int { processedRequests.count }

    private static func makeSampleID(sessionID: SessionID, sequence: Int64) -> String {
        "\(sessionID.rawValue):\(sequence)"
    }

    private static func fingerprint(for batch: ReadBatch) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(batch) else {
            return batch.requestID.rawValue
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
