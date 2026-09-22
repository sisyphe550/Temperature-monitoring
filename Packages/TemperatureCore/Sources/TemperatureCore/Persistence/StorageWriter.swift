import Foundation

struct StorageWriter {
    let flushRecords: Int
    let flushMS: Int
    let maxOldestAgeMS: Int
    var pausedForTesting = false

    init(configuration: RuntimeConfiguration) {
        flushRecords = configuration.writerFlushRecords
        flushMS = configuration.writerFlushMS
        maxOldestAgeMS = configuration.writerMaxOldestAgeMS
    }

    func shouldFlush(pendingRecords: Int, oldestAgeMS: Int?) -> Bool {
        guard pendingRecords > 0 else {
            return false
        }
        if let oldestAgeMS, oldestAgeMS >= flushMS {
            return true
        }
        return pendingRecords >= flushRecords
    }

    func validateOldestAge(_ oldestAgeMS: Int?) throws {
        guard let oldestAgeMS, oldestAgeMS > maxOldestAgeMS else {
            return
        }
        throw StorageWriterError.oldestAgeExceeded
    }
}

enum StorageWriterError: Error, Equatable {
    case oldestAgeExceeded
    case paused
}
