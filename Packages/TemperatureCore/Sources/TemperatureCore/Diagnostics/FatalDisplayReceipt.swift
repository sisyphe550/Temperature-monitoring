import Foundation

public struct FatalDisplayReceipt: Sendable, Equatable {
    public let failure: MonitorFailure
    public let visibleAt: Timestamp
    public let exitDeadline: Timestamp
    public let reportPath: String?

    public init(
        failure: MonitorFailure,
        visibleAt: Timestamp,
        exitDeadline: Timestamp,
        reportPath: String?
    ) {
        self.failure = failure
        self.visibleAt = visibleAt
        self.exitDeadline = exitDeadline
        self.reportPath = reportPath
    }

    public init(
        failure: MonitorFailure,
        visibleAt: Timestamp,
        configuration: RuntimeConfiguration,
        reportPath: String?
    ) {
        self.failure = failure
        self.visibleAt = visibleAt
        exitDeadline = Timestamp(
            elapsedNS: visibleAt.elapsedNS + Int64(configuration.fatalDisplayMS) * 1_000_000,
            wallUnixNS: visibleAt.wallUnixNS + Int64(configuration.fatalDisplayMS) * 1_000_000
        )
        self.reportPath = reportPath
    }

    public func hasExpired(at timestamp: Timestamp) -> Bool {
        timestamp.elapsedNS >= exitDeadline.elapsedNS
    }

    public func remainingMS(at timestamp: Timestamp) -> Int {
        max(0, Int((exitDeadline.elapsedNS - timestamp.elapsedNS) / 1_000_000))
    }
}
