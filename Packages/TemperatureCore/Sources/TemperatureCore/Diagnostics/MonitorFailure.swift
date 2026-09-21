import Foundation

public struct MonitorFailure: Error, Codable, Sendable, Equatable {
    public let code: MonitorErrorCode
    public let severity: Severity
    public let component: String
    public let operation: String
    public let retryCount: Int
    public let sourceID: SourceID?
    public let underlyingCode: String?

    public init(
        code: MonitorErrorCode,
        severity: Severity,
        component: String,
        operation: String,
        retryCount: Int,
        sourceID: SourceID?,
        underlyingCode: String?
    ) {
        self.code = code
        self.severity = severity
        self.component = component
        self.operation = operation
        self.retryCount = retryCount
        self.sourceID = sourceID
        self.underlyingCode = underlyingCode
    }
}
