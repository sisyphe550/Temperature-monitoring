import Foundation
import TemperatureCore

public actor ProcessingCoordinator {
    private let clock: MonitorClock
    private let configuration: RuntimeConfiguration
    private let reservation: PersistenceReservationCapability
    private let engine: MonitorEngine
    private let sampling: SamplingService
    private var catalogGeneration: UInt64 = 0
    private var watermarkTask: Task<Void, Never>?
    private var nextWatermarkOrdinal: Int64 = 1
    private(set) var lastAcceptFailure: MonitorFailure?

    public init(
        clock: MonitorClock,
        client: any SensorClient,
        reservation: PersistenceReservationCapability,
        engine: MonitorEngine,
        configuration: RuntimeConfiguration
    ) {
        self.clock = clock
        self.configuration = configuration
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
            onRead: { [weak self] event in
                await self?.handleRead(event)
            }
        )
        startWatermarkLoop()
    }

    public func stop() async {
        watermarkTask?.cancel()
        watermarkTask = nil
        await sampling.stop()
    }

    public func suspendForSleep() async throws {
        watermarkTask?.cancel()
        watermarkTask = nil
        await sampling.stop()
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
        await sampling.start(
            catalog: catalog,
            willRead: { [engine] _, plannedStart in
                await engine.registerInFlightReading(startElapsedNS: plannedStart)
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
        let starts = event.batch.readings.map(\.started.elapsedNS)
        if event.batch.generation < catalogGeneration {
            await reservation.cancel(event.lease)
            for start in starts {
                await engine.unregisterInFlightReading(startElapsedNS: start)
            }
            return
        }

        do {
            _ = try await engine.accept(event.batch, lease: event.lease)
            lastAcceptFailure = nil
        } catch {
            lastAcceptFailure = error as? MonitorFailure
            await reservation.cancel(event.lease)
            for start in starts {
                await engine.unregisterInFlightReading(startElapsedNS: start)
            }
            return
        }

        for start in starts {
            await engine.unregisterInFlightReading(startElapsedNS: start)
        }
        await advanceWatermarkIfDue()
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
        let now = clock.now()
        let safeElapsed = await engine.safeWatermarkElapsedNS(at: now)
        guard safeElapsed >= 1_000_000_000 else {
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

        let timestamp = Timestamp(elapsedNS: safeElapsed, wallUnixNS: now.wallUnixNS)
        do {
            _ = try await engine.advance(to: timestamp, lease: lease)
        } catch {
            await reservation.cancel(lease)
        }
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
