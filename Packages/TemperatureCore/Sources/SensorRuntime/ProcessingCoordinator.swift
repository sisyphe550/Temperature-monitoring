import Foundation
import TemperatureCore

public actor ProcessingCoordinator {
    private let clock: MonitorClock
    private let configuration: RuntimeConfiguration
    private let reservation: PersistenceReservationCapability
    private let engine: MonitorEngine
    private let sampling: SamplingService
    private let diagnosticSink: (@Sendable (MonitorFailure) async -> Void)?
    private var catalogGeneration: UInt64 = 0
    private var watermarkTask: Task<Void, Never>?
    private var nextWatermarkOrdinal: Int64 = 1
    private var watermarkAdvanceInFlight = false
    private var lastWatermarkElapsedNS: Int64 = 0
    private(set) var lastAcceptFailure: MonitorFailure?

    public init(
        clock: MonitorClock,
        client: any SensorClient,
        reservation: PersistenceReservationCapability,
        engine: MonitorEngine,
        configuration: RuntimeConfiguration,
        diagnosticSink: (@Sendable (MonitorFailure) async -> Void)? = nil
    ) {
        self.clock = clock
        self.configuration = configuration
        self.diagnosticSink = diagnosticSink
        self.reservation = reservation
        self.engine = engine
        sampling = SamplingService(
            clock: clock,
            client: client,
            reservation: reservation,
            configuration: configuration
        )
    }

    public func start(catalog: QualifiedSourceCatalog) async {
        catalogGeneration = catalog.generation
        nextWatermarkOrdinal = 1
        await sampling.start(
            catalog: catalog,
            willRead: { [engine] _, plannedStart in
                await engine.registerInFlightReading(startElapsedNS: plannedStart)
            },
            didFinishRead: { [weak self, engine] _, plannedStart in
                await engine.unregisterInFlightReading(startElapsedNS: plannedStart)
                await self?.advanceWatermarkIfDue()
            },
            onFailure: { [weak self] failure, _ in
                await self?.recordFailure(failure)
            },
            onRecoveredCatalog: { [weak self] recovered in
                try await self?.installRecoveredCatalog(recovered)
            },
            onOptionalAvailability: { [engine] kind, failure in
                let sensorKind: SensorKind = kind == .ssd ? .ssd : .battery
                await engine.setOptionalAvailability(kind: sensorKind, failure: failure)
            },
            onRead: { [weak self] event in
                await self?.handleRead(event)
            }
        )
        startWatermarkLoop()
    }

    public func stop() async {
        let watermark = watermarkTask
        watermark?.cancel()
        watermarkTask = nil
        await sampling.stop()
        await watermark?.value
    }

    public func suspendForSleep() async throws {
        let watermark = watermarkTask
        watermark?.cancel()
        watermarkTask = nil
        await sampling.suspendForSleep()
        await watermark?.value
        await waitForSamplingIdle()
        await advanceWatermarkIfDue()
        let timestamp = clock.now()
        let gaps = try await engine.openSleepGaps(at: timestamp)
        guard !gaps.isEmpty else {
            return
        }
        let gapID = makeGapID()
        let lease = try await reservation.reserve(
            owner: .gap(gapID),
            generation: catalogGeneration,
            maxRecords: configuration.writerReserveRecordsPerEvent,
            maxBytes: configuration.writerMaxPayloadBytes
        )
        do {
            _ = try await engine.commitLifecycleTransition(gaps: gaps, segments: [], lease: lease)
        } catch {
            await reservation.cancel(lease)
            throw error
        }
    }

    public func resumeAfterWake(catalog: QualifiedSourceCatalog) async throws {
        catalogGeneration = catalog.generation
        let timestamp = clock.now()
        let transition = try await engine.closeOpenGapsForWake(at: timestamp)
        if !transition.gaps.isEmpty {
            let gapID = makeGapID()
            let lease = try await reservation.reserve(
                owner: .gap(gapID),
                generation: catalogGeneration,
                maxRecords: configuration.writerReserveRecordsPerEvent,
                maxBytes: configuration.writerMaxPayloadBytes
            )
            do {
                _ = try await engine.commitLifecycleTransition(
                    gaps: transition.gaps,
                    segments: transition.segments,
                    lease: lease
                )
            } catch {
                await reservation.cancel(lease)
                throw error
            }
        }
        let definitions = try SeriesCatalogBuilder.definitions(from: catalog)
        let gaps = await engine.closeOpenGapsForSourceChange(at: clock.now())
        if !gaps.isEmpty {
            let lease = try await reservation.reserve(owner: .gap(makeGapID()), generation: catalogGeneration,
                maxRecords: configuration.writerReserveRecordsPerEvent, maxBytes: configuration.writerMaxPayloadBytes)
            do { _ = try await engine.commitLifecycleTransition(gaps: gaps, segments: [], lease: lease) }
            catch { await reservation.cancel(lease); throw error }
        }
        await engine.replaceDefinitions(definitions, qualifiedSources: catalog.available,
            capabilityValues: try SeriesCatalogBuilder.unavailableValues(from: catalog))
        await sampling.start(
            catalog: catalog,
            willRead: { [engine] _, plannedStart in
                await engine.registerInFlightReading(startElapsedNS: plannedStart)
            },
            didFinishRead: { [weak self, engine] _, plannedStart in
                await engine.unregisterInFlightReading(startElapsedNS: plannedStart)
                await self?.advanceWatermarkIfDue()
            },
            onFailure: { [weak self] failure, _ in
                await self?.recordFailure(failure)
            },
            onRecoveredCatalog: { [weak self] recovered in
                try await self?.installRecoveredCatalog(recovered)
            },
            onOptionalAvailability: { [engine] kind, failure in
                let sensorKind: SensorKind = kind == .ssd ? .ssd : .battery
                await engine.setOptionalAvailability(kind: sensorKind, failure: failure)
            },
            onRead: { [weak self] event in
                await self?.handleRead(event)
            }
        )
        startWatermarkLoop()
    }

    public func setCPUPeriod(milliseconds: Int) async {
        await sampling.setCPUPeriod(milliseconds: milliseconds)
    }

    public func samplingStatistics() async -> SamplingStatistics {
        await sampling.statistics()
    }

    private func handleRead(_ event: SamplingReadEvent) async {
        if event.batch.generation < catalogGeneration {
            await reservation.cancel(event.lease)
            return
        }

        do {
            _ = try await engine.accept(event.batch, lease: event.lease)
            if lastAcceptFailure?.severity != .fatal { lastAcceptFailure = nil }
        } catch {
            let failure = (error as? MonitorFailure) ?? MonitorFailure(code: .processingValidate, severity: .fatal,
                component: "ProcessingCoordinator", operation: "accept", retryCount: 0, sourceID: nil, underlyingCode: String(describing: error))
            await recordFailure(failure)
            await reservation.cancel(event.lease)
            return
        }

    }

    private func startWatermarkLoop() {
        watermarkTask?.cancel()
        watermarkTask = Task {
            while !Task.isCancelled {
                let shouldContinue = await self.runWatermarkCycle()
                if !shouldContinue {
                    return
                }
            }
        }
    }

    private func runWatermarkCycle() async -> Bool {
        await advanceWatermarkIfDue()
        let now = clock.now().elapsedNS
        let nextSecond = ((now / 1_000_000_000) + 1) * 1_000_000_000
        do {
            try await clock.sleep(untilElapsedNS: nextSecond)
            return true
        } catch {
            return false
        }
    }

    private func advanceWatermarkIfDue() async {
        guard !watermarkAdvanceInFlight, lastAcceptFailure?.severity != .fatal else { return }
        watermarkAdvanceInFlight = true
        defer { watermarkAdvanceInFlight = false }
        let now = clock.now()
        let safeElapsed = await engine.safeWatermarkElapsedNS(at: now)
        let closedThrough = (safeElapsed / 1_000_000_000) * 1_000_000_000
        guard closedThrough > lastWatermarkElapsedNS else {
            return
        }
        let watermarkID = makeWatermarkID()
        let lease: PersistenceLease
        do {
            lease = try await reservation.reserve(
                owner: .watermark(watermarkID),
                generation: catalogGeneration,
                maxRecords: configuration.writerReserveRecordsPerEvent,
                maxBytes: configuration.writerMaxPayloadBytes
            )
        } catch {
            return
        }

        let timestamp = Timestamp(elapsedNS: closedThrough, wallUnixNS: now.wallUnixNS)
        do {
            _ = try await engine.advance(to: timestamp, lease: lease)
            lastWatermarkElapsedNS = closedThrough
        } catch {
            await reservation.cancel(lease)
            let failure = (error as? MonitorFailure) ?? MonitorFailure(code: .processingAggregate, severity: .fatal,
                component: "ProcessingCoordinator", operation: "watermark", retryCount: 0, sourceID: nil, underlyingCode: String(describing: error))
            await recordFailure(failure)
        }
    }

    func reportFailure(_ failure: MonitorFailure) async { await recordFailure(failure) }

    private func recordFailure(_ failure: MonitorFailure) async {
        // A structural processing failure must not be replaced by a later sensor retry.
        guard lastAcceptFailure?.severity != .fatal else { return }
        lastAcceptFailure = failure
        await diagnosticSink?(failure)
        if failure.severity == .fatal { await sampling.requestStop() }
    }

    public func prepareForWakeMaintenance() async throws {
        // IO has stopped. Close only windows containing real pre-sleep samples
        // before TTL checks require their persisted parents.
        await advanceWatermarkIfDue()
        if let failure = lastAcceptFailure, failure.severity == .fatal { throw failure }
    }

    private func installRecoveredCatalog(_ catalog: QualifiedSourceCatalog) async throws {
        let definitions = try SeriesCatalogBuilder.definitions(from: catalog)
        let gaps = await engine.closeOpenGapsForSourceChange(at: clock.now())
        if !gaps.isEmpty {
            let lease = try await reservation.reserve(owner: .gap(makeGapID()), generation: catalogGeneration,
                maxRecords: configuration.writerReserveRecordsPerEvent, maxBytes: configuration.writerMaxPayloadBytes)
            do { _ = try await engine.commitLifecycleTransition(gaps: gaps, segments: [], lease: lease) }
            catch { await reservation.cancel(lease); throw error }
        }
        await engine.replaceDefinitions(definitions, qualifiedSources: catalog.available,
            capabilityValues: try SeriesCatalogBuilder.unavailableValues(from: catalog))
        catalogGeneration = catalog.generation
    }

    private func makeWatermarkID() -> WatermarkEventID {
        let ordinal = nextWatermarkOrdinal
        nextWatermarkOrdinal += 1
        let raw = String(format: "00000000-0000-4000-8000-%012d", ordinal)
        return (try? WatermarkEventID(validating: raw)) ?? WatermarkEventID(UUID())
    }

    private func makeGapID() -> GapID {
        let ordinal = nextWatermarkOrdinal
        nextWatermarkOrdinal += 1
        let raw = String(format: "00000000-0000-4000-8000-%012d", ordinal)
        return (try? GapID(validating: raw)) ?? GapID(UUID())
    }

    private func waitForSamplingIdle() async {
        while await sampling.isReadInFlight {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}
