import Foundation

enum SampleValidation {
    static let absoluteZeroCelsius = -273.15

    static func validateSuccessValue(_ valueC: Double) throws {
        guard valueC.isFinite else {
            throw ProcessingValidationError.invalidTemperature
        }
        guard valueC >= absoluteZeroCelsius else {
            throw ProcessingValidationError.invalidTemperature
        }
    }
}

enum ProcessingValidationError: Error, Sendable, Equatable {
    case invalidTemperature
    case staleGeneration
    case staleElapsed
    case duplicateSampleID
    case nonMonotonicElapsed
    case requestContentMismatch
    case invalidLease
    case seriesLimitExceeded
}
