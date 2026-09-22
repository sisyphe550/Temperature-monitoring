import Foundation
import os

public struct FatalReport: Codable, Sendable, Equatable {
    public let frozenFailure: MonitorFailure
    public let sessionID: SessionID
    public let appVersion: String
    public let model: String
    public let osBuild: String
    public let incompleteShutdownSteps: [String]
    public let writtenAt: Date

    public init(
        frozenFailure: MonitorFailure,
        sessionID: SessionID,
        appVersion: String,
        model: String,
        osBuild: String,
        incompleteShutdownSteps: [String],
        writtenAt: Date
    ) {
        self.frozenFailure = frozenFailure
        self.sessionID = sessionID
        self.appVersion = appVersion
        self.model = model
        self.osBuild = osBuild
        self.incompleteShutdownSteps = incompleteShutdownSteps
        self.writtenAt = writtenAt
    }
}

public struct ReportWriteResult: Sendable, Equatable {
    public let url: URL?
    public let fallbackText: String

    public init(url: URL?, fallbackText: String) {
        self.url = url
        self.fallbackText = fallbackText
    }
}

private struct ReportPayload: Codable {
    let error_code: String
    let severity: String
    let component: String
    let operation: String
    let retry_count: Int
    let session_id: String
    let app_version: String
    let model: String
    let os_build: String
    let underlying_error: String?
    let incomplete_shutdown_steps: [String]
    let written_at: Date
}

public final class ReportWriter: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.temperaturemonitor.app", category: "FatalReport")

    private let directory: URL
    private let configuration: RuntimeConfiguration
    private let encoder: JSONEncoder

    public init(directory: URL, configuration: RuntimeConfiguration) {
        self.directory = directory
        self.configuration = configuration
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func write(_ report: FatalReport) throws -> ReportWriteResult {
        let fallback = makeFallbackText(for: report)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.isWritableFile(atPath: directory.path) else {
            Self.logFallback(fallback)
            return ReportWriteResult(url: nil, fallbackText: fallback)
        }

        let reportsDirectory = directory.appendingPathComponent("reports", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
            let payload = ReportPayload(report: report)
            let data = try encoder.encode(payload)
            guard data.count <= configuration.reportFileLimitBytes else {
                Self.logFallback(fallback)
                return ReportWriteResult(url: nil, fallbackText: fallback)
            }

            let fileName = "fatal-\(Int(report.writtenAt.timeIntervalSince1970)).json"
            let url = reportsDirectory.appendingPathComponent(fileName)
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                Self.logFallback(fallback)
                return ReportWriteResult(url: nil, fallbackText: fallback)
            }

            try enforceReportRetention(in: reportsDirectory)
            return ReportWriteResult(url: url, fallbackText: fallback)
        } catch {
            Self.logFallback(fallback)
            return ReportWriteResult(url: nil, fallbackText: fallback)
        }
    }

    private func enforceReportRetention(in reportsDirectory: URL) throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: reportsDirectory,
            includingPropertiesForKeys: [.creationDateKey]
        ).filter { $0.pathExtension == "json" }
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return lhs < rhs
            }

        let overflow = files.count - configuration.reportFileCount
        if overflow > 0 {
            for file in files.prefix(overflow) {
                try FileManager.default.removeItem(at: file)
            }
        }

        let ttl = TimeInterval(configuration.diagnosticsTTLDays * 24 * 60 * 60)
        let now = Date()
        for file in files {
            guard let created = try file.resourceValues(forKeys: [.creationDateKey]).creationDate else {
                continue
            }
            if now.timeIntervalSince(created) > ttl {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func makeFallbackText(for report: FatalReport) -> String {
        [
            report.frozenFailure.code.rawValue,
            report.frozenFailure.component,
            report.frozenFailure.operation,
            report.frozenFailure.underlyingCode ?? "unknown",
        ].joined(separator: " | ")
    }

    private static func logFallback(_ text: String) {
        logger.error("\(text, privacy: .public)")
        fputs("TemperatureMonitor fatal report: \(text)\n", stderr)
    }
}

private extension ReportPayload {
    init(report: FatalReport) {
        error_code = report.frozenFailure.code.rawValue
        severity = report.frozenFailure.severity.rawValue
        component = report.frozenFailure.component
        operation = report.frozenFailure.operation
        retry_count = report.frozenFailure.retryCount
        session_id = report.sessionID.rawValue
        app_version = report.appVersion
        model = report.model
        os_build = report.osBuild
        underlying_error = report.frozenFailure.underlyingCode
        incomplete_shutdown_steps = report.incompleteShutdownSteps
        written_at = report.writtenAt
    }
}
