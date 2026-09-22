import Foundation

struct BoundedQueue {
    enum ReservationState: Equatable {
        case active
        case consumed
        case cancelled
    }

    struct Reservation: Equatable {
        let id: UUID
        let owner: PersistenceOwner
        let generation: UInt64
        let maxRecords: Int
        let maxBytes: Int
        var state: ReservationState
    }

    struct QueuedBatch: Equatable {
        let batch: PersistenceBatch
        let reservationID: UUID
        let enqueuedAt: Date
        let recordCount: Int
        let byteCount: Int
    }

    private(set) var reservations: [UUID: Reservation] = [:]
    private(set) var pending: [QueuedBatch] = []
    private(set) var inFlightRecords = 0
    private(set) var inFlightBytes = 0
    private(set) var backpressureLatched = false

    let maxRecords: Int
    let maxBytes: Int
    let pauseAtRecords: Int
    let resumeBelowRecords: Int

    init(configuration: RuntimeConfiguration) {
        maxRecords = configuration.writerMaxRecords
        maxBytes = configuration.writerMaxPayloadBytes
        pauseAtRecords = configuration.writerPauseAtRecords
        resumeBelowRecords = configuration.writerResumeBelowRecords
    }

    var totalRecords: Int {
        reservedRecords + pendingRecords + inFlightRecords
    }

    var totalBytes: Int {
        reservedBytes + pendingBytes + inFlightBytes
    }

    var reservedRecords: Int {
        reservations.values.reduce(into: 0) { partial, reservation in
            guard reservation.state == .active else {
                return
            }
            partial += reservation.maxRecords
        }
    }

    var reservedBytes: Int {
        reservations.values.reduce(into: 0) { partial, reservation in
            guard reservation.state == .active else {
                return
            }
            partial += reservation.maxBytes
        }
    }

    var pendingRecords: Int {
        pending.reduce(into: 0) { $0 += $1.recordCount }
    }

    var pendingBytes: Int {
        pending.reduce(into: 0) { $0 += $1.byteCount }
    }

    var acceptsNewReservations: Bool {
        guard totalRecords < maxRecords, totalBytes < maxBytes else {
            return false
        }
        return !backpressureLatched
    }

    mutating func registerReservation(
        id: UUID,
        owner: PersistenceOwner,
        generation: UInt64,
        reservedRecords: Int,
        reservedBytes: Int
    ) throws {
        updateBackpressureLatch()
        guard acceptsNewReservations else {
            throw BoundedQueueError.backpressure
        }
        guard reservedRecords > 0, reservedBytes > 0 else {
            throw BoundedQueueError.invalidCapacity
        }
        guard totalRecords + reservedRecords <= maxRecords, totalBytes + reservedBytes <= maxBytes else {
            throw BoundedQueueError.capacityExceeded
        }
        reservations[id] = Reservation(
            id: id,
            owner: owner,
            generation: generation,
            maxRecords: reservedRecords,
            maxBytes: reservedBytes,
            state: .active
        )
        updateBackpressureLatch()
    }

    mutating func cancelReservation(id: UUID) throws {
        guard var reservation = reservations[id] else {
            throw BoundedQueueError.unknownReservation
        }
        guard reservation.state == .active else {
            return
        }
        reservation.state = .cancelled
        reservations[id] = reservation
        updateBackpressureLatch()
    }

    func validateReservation(
        id: UUID,
        owner: PersistenceOwner,
        generation: UInt64,
        recordCount: Int,
        byteCount: Int
    ) throws {
        guard let reservation = reservations[id] else {
            throw BoundedQueueError.unknownReservation
        }
        guard reservation.state == .active else {
            throw BoundedQueueError.reservationNotActive
        }
        guard reservation.owner == owner, reservation.generation == generation else {
            throw BoundedQueueError.ownerMismatch
        }
        guard recordCount <= reservation.maxRecords, byteCount <= reservation.maxBytes else {
            throw BoundedQueueError.capacityExceeded
        }
    }

    mutating func consumeReservation(
        id: UUID,
        owner: PersistenceOwner,
        generation: UInt64,
        batch: PersistenceBatch,
        recordCount: Int,
        byteCount: Int,
        now: Date
    ) throws {
        try validateReservation(
            id: id,
            owner: owner,
            generation: generation,
            recordCount: recordCount,
            byteCount: byteCount
        )
        guard var reservation = reservations[id] else {
            throw BoundedQueueError.unknownReservation
        }
        reservation.state = .consumed
        reservations[id] = reservation
        pending.append(
            QueuedBatch(
                batch: batch,
                reservationID: id,
                enqueuedAt: now,
                recordCount: recordCount,
                byteCount: byteCount
            )
        )
        updateBackpressureLatch()
    }

    mutating func beginInFlight(records: Int, bytes: Int) {
        inFlightRecords += records
        inFlightBytes += bytes
    }

    mutating func finishInFlight(records: Int, bytes: Int) {
        inFlightRecords = max(0, inFlightRecords - records)
        inFlightBytes = max(0, inFlightBytes - bytes)
        updateBackpressureLatch()
    }

    mutating func dequeueFlushable(
        flushRecordThreshold: Int,
        flushAgeMS: Int,
        now: Date
    ) -> [QueuedBatch] {
        guard !pending.isEmpty else {
            return []
        }
        let oldestAgeMS = Int(now.timeIntervalSince(pending[0].enqueuedAt) * 1000)
        let pendingTotal = pendingRecords
        guard pendingTotal >= flushRecordThreshold || oldestAgeMS >= flushAgeMS else {
            return []
        }

        var selected: [QueuedBatch] = []
        var accumulated = 0
        var index = 0
        while index < pending.count, accumulated < flushRecordThreshold {
            let item = pending[index]
            selected.append(item)
            accumulated += item.recordCount
            index += 1
        }
        pending.removeFirst(index)
        return selected
    }

    mutating func requeueFront(_ batches: [QueuedBatch]) {
        pending.insert(contentsOf: batches, at: 0)
        updateBackpressureLatch()
    }

    mutating func dequeueThrough(batchID: BatchID) throws -> [QueuedBatch] {
        guard let index = pending.firstIndex(where: { $0.batch.batchID == batchID }) else {
            throw BoundedQueueError.unknownBatch
        }
        let selected = Array(pending[0...index])
        pending.removeFirst(index + 1)
        updateBackpressureLatch()
        return selected
    }

    func oldestPendingAgeMS(now: Date) -> Int? {
        guard let first = pending.first else {
            return nil
        }
        return Int(now.timeIntervalSince(first.enqueuedAt) * 1000)
    }

    @discardableResult
    mutating func updateBackpressureLatch() -> Bool {
        if totalRecords >= pauseAtRecords {
            backpressureLatched = true
        } else if totalRecords < resumeBelowRecords {
            backpressureLatched = false
        }
        return backpressureLatched
    }
}

enum BoundedQueueError: Error, Equatable {
    case backpressure
    case capacityExceeded
    case invalidCapacity
    case unknownReservation
    case reservationNotActive
    case ownerMismatch
    case unknownBatch
}
