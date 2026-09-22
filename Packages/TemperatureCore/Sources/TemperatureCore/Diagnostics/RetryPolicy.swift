import Foundation

public enum RetryDomain: String, Sendable, Equatable {
    case sensor
    case database
    case processing
    case uiHistory
}

public struct RetryPolicy: Sendable {
    public let configuration: RuntimeConfiguration

    public init(configuration: RuntimeConfiguration) {
        self.configuration = configuration
    }

    public func waitsMS(for domain: RetryDomain) -> [Int] {
        switch domain {
        case .sensor:
            configuration.sensorRetryMS
        case .database:
            configuration.databaseRetryMS
        case .processing:
            configuration.processingRetryMS
        case .uiHistory:
            configuration.uiRetryMS
        }
    }

    public func additionalAttempts(for domain: RetryDomain) -> Int {
        waitsMS(for: domain).count
    }

    public func waitMS(for domain: RetryDomain, afterFailureIndex failureIndex: Int) -> Int? {
        let waits = waitsMS(for: domain)
        guard failureIndex >= 0, failureIndex < waits.count else {
            return nil
        }
        return waits[failureIndex]
    }

    public func isRetryable(_ failure: MonitorFailure, domain: RetryDomain) -> Bool {
        switch failure.code {
        case .databaseIntegrity,
             .databaseSchema,
             .databaseCorrupt,
             .databaseBackpressure,
             .databaseCapacity,
             .processingValidate,
             .sensorProtocol,
             .sensorTag,
             .unsupportedPlatform,
             .appInit:
            return false
        case .databaseOpen:
            guard domain == .database else {
                return false
            }
            switch failure.underlyingCode {
            case "busy", "locked":
                return true
            default:
                return false
            }
        case .databaseWrite,
             .databaseRead,
             .sensorRead,
             .sensorTimeout,
             .sensorValue,
             .processingEMA,
             .processingAggregate,
             .processingTrend,
             .uiData:
            return true
        case .sensorDiscover,
             .databaseClean,
             .databaseInit,
             .uiRender:
            return false
        }
    }
}
