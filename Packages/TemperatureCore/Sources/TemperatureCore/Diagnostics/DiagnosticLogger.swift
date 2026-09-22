import Foundation

public struct DiagnosticLogEntry: Codable, Sendable, Equatable {
    public let errorCode: String
    public let severity: String
    public let timestamp: Date
    public let component: String
    public let operation: String
    public let retryCount: Int
    public let sessionID: String?
    public let appVersion: String
    public let model: String
    public let osBuild: String
    public let underlyingError: String?

    public init(
        errorCode: String,
        severity: String,
        timestamp: Date,
        component: String,
        operation: String,
        retryCount: Int,
        sessionID: String?,
        appVersion: String,
        model: String,
        osBuild: String,
        underlyingError: String?
    ) {
        self.errorCode = errorCode
        self.severity = severity
        self.timestamp = timestamp
        self.component = component
        self.operation = operation
        self.retryCount = retryCount
        self.sessionID = sessionID
        self.appVersion = appVersion
        self.model = model
        self.osBuild = osBuild
        self.underlyingError = underlyingError
    }

    public init(failure: MonitorFailure, context: DiagnosticContext, timestamp: Date = Date()) {
        errorCode = failure.code.rawValue
        severity = failure.severity.rawValue
        self.timestamp = timestamp
        component = failure.component
        operation = failure.operation
        retryCount = failure.retryCount
        sessionID = context.sessionID.rawValue
        appVersion = context.appVersion
        model = context.model
        osBuild = context.osBuild
        underlyingError = failure.underlyingCode
    }
}

public struct DiagnosticContext: Sendable, Equatable {
    public let sessionID: SessionID
    public let appVersion: String
    public let model: String
    public let osBuild: String

    public init(sessionID: SessionID, appVersion: String, model: String, osBuild: String) {
        self.sessionID = sessionID
        self.appVersion = appVersion
        self.model = model
        self.osBuild = osBuild
    }
}

public final class DiagnosticLogger: @unchecked Sendable {
    private let directory: URL
    private let configuration: RuntimeConfiguration
    private let encoder: JSONEncoder
    private let lock = NSLock()
    private var activeFileIndex = 0

    public init(directory: URL, configuration: RuntimeConfiguration) {
        self.directory = directory
        self.configuration = configuration
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        activeFileIndex = (try? Self.latestLogIndex(in: directory)) ?? 0
    }

    public func append(_ entry: DiagnosticLogEntry) throws {
        lock.lock()
        defer { lock.unlock() }

        let line = try encoder.encode(entry) + Data([0x0A])
        let url = logURL(for: activeFileIndex)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)

        if try handle.offset() >= configuration.logRotateBytes {
            activeFileIndex += 1
            try enforceRetention()
        }
    }

    public func pruneExpired(now: Date) {
        lock.lock()
        defer { lock.unlock() }
        let ttl = TimeInterval(configuration.diagnosticsTTLDays * 24 * 60 * 60)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return
        }
        for file in files where file.lastPathComponent.hasPrefix("diagnostic-") {
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate else {
                continue
            }
            if now.timeIntervalSince(modified) > ttl {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func logURL(for index: Int) -> URL {
        directory.appendingPathComponent(String(format: "diagnostic-%03d.jsonl", index))
    }

    private func enforceRetention() throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey]
        ).filter { $0.lastPathComponent.hasPrefix("diagnostic-") && $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let overflow = files.count - configuration.logFileCount
        if overflow > 0 {
            for file in files.prefix(overflow) {
                try FileManager.default.removeItem(at: file)
            }
        }
    }

    private static func latestLogIndex(in directory: URL) throws -> Int {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("diagnostic-") }
        return files.compactMap { url -> Int? in
            let name = url.deletingPathExtension().lastPathComponent
            return Int(name.replacingOccurrences(of: "diagnostic-", with: ""))
        }.max() ?? 0
    }
}
