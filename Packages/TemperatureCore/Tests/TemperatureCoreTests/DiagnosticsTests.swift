import Foundation
import Testing
@testable import TemperatureCore

@Suite struct DiagnosticsTests {
    @Test func loggerRotatesAtConfiguredSize() throws {
        let directory = try makeDiagnosticsDirectory()
        let configuration = try makeDiagnosticsConfiguration(logRotateBytes: 256, logFileCount: 5)
        let logger = DiagnosticLogger(directory: directory, configuration: configuration)

        let entry = sampleLogEntry()
        for _ in 0..<20 {
            try logger.append(entry)
        }

        let files = try logFiles(in: directory)
        #expect(files.count >= 2)
    }

    @Test func loggerRetainsAtMostConfiguredFileCount() throws {
        let directory = try makeDiagnosticsDirectory()
        let configuration = try makeDiagnosticsConfiguration(logRotateBytes: 64, logFileCount: 3)
        let logger = DiagnosticLogger(directory: directory, configuration: configuration)
        let entry = sampleLogEntry()

        for _ in 0..<100 {
            try logger.append(entry)
        }

        #expect(try logFiles(in: directory).count <= 3)
    }

    @Test func loggerPrunesFilesOlderThanTTL() throws {
        let directory = try makeDiagnosticsDirectory()
        let configuration = try makeDiagnosticsConfiguration(logRotateBytes: 10_000, logFileCount: 5)
        let logger = DiagnosticLogger(directory: directory, configuration: configuration)
        let staleURL = directory.appendingPathComponent("diagnostic-stale.jsonl")
        try Data("{}\\n".utf8).write(to: staleURL)
        let staleDate = Date().addingTimeInterval(-15 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: staleDate], ofItemAtPath: staleURL.path)

        try logger.append(sampleLogEntry())
        logger.pruneExpired(now: Date())

        #expect(FileManager.default.fileExists(atPath: staleURL.path) == false)
    }

    @Test func reportWriterCreatesBoundedReportFile() throws {
        let directory = try makeDiagnosticsDirectory()
        let configuration = try Configuration.bundledDefaults()
        let writer = ReportWriter(directory: directory, configuration: configuration)
        let report = sampleFatalReport()

        let result = try writer.write(report)

        #expect(result.url != nil)
        #expect(result.fallbackText.contains("SENSOR-READ-002"))
        if let url = result.url {
            let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64
            #expect((size ?? 0) <= Int64(configuration.reportFileLimitBytes))
        }
    }

    @Test func reportWriterKeepsAtMostConfiguredReportCount() throws {
        let directory = try makeDiagnosticsDirectory()
        let configuration = try makeDiagnosticsConfiguration(
            logRotateBytes: 10_000,
            logFileCount: 5,
            reportFileCount: 3
        )
        let writer = ReportWriter(directory: directory, configuration: configuration)

        for index in 0..<5 {
            _ = try writer.write(sampleFatalReport(codeSuffix: index))
        }

        let reports = try reportFiles(in: directory)
        #expect(reports.count <= 3)
    }

    @Test func reportWriterReturnsFallbackWhenDirectoryIsNotWritable() throws {
        let directory = try makeDiagnosticsDirectory()
        let fileURL = directory.appendingPathComponent("blocked")
        try Data("x".utf8).write(to: fileURL)
        let configuration = try Configuration.bundledDefaults()
        let writer = ReportWriter(directory: fileURL, configuration: configuration)

        let result = try writer.write(sampleFatalReport())

        #expect(result.url == nil)
        #expect(result.fallbackText.contains("SENSOR-READ-002"))
        #expect(result.fallbackText.contains("SamplingService"))
    }

    @Test func reportWriterDoesNotIncludeMachineSerialField() throws {
        let directory = try makeDiagnosticsDirectory()
        let configuration = try Configuration.bundledDefaults()
        let writer = ReportWriter(directory: directory, configuration: configuration)
        let result = try writer.write(sampleFatalReport())
        let url = try #require(result.url)
        let json = try String(contentsOf: url, encoding: .utf8)
        #expect(json.contains("error_code"))
        #expect(json.contains("serial") == false)
    }
}

private func makeDiagnosticsDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("DiagnosticsTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func makeDiagnosticsConfiguration(
    logRotateBytes: Int,
    logFileCount: Int,
    reportFileCount: Int? = nil
) throws -> RuntimeConfiguration {
    var defaults = try Configuration.bundledDefaults()
    let encoder = JSONEncoder()
    var data = try encoder.encode(defaults)
    guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw ConfigurationError.invalidValue("diagnostics_test_config")
    }
    object["log_rotate_bytes"] = logRotateBytes
    object["log_file_count"] = logFileCount
    if let reportFileCount {
        object["report_file_count"] = reportFileCount
    }
    data = try JSONSerialization.data(withJSONObject: object)
    return try JSONDecoder().decode(RuntimeConfiguration.self, from: data)
}

private func sampleLogEntry() -> DiagnosticLogEntry {
    DiagnosticLogEntry(
        errorCode: MonitorErrorCode.sensorRead.rawValue,
        severity: Severity.fatal.rawValue,
        timestamp: Date(),
        component: "SamplingService",
        operation: "read",
        retryCount: 1,
        sessionID: "00000000-0000-4000-8000-000000000801",
        appVersion: "0.1.0-test",
        model: "Mac16,13",
        osBuild: "24G419",
        underlyingError: "transport_error"
    )
}

private func sampleFatalReport(codeSuffix: Int = 0) -> FatalReport {
    FatalReport(
        frozenFailure: MonitorFailure(
            code: .sensorRead,
            severity: .fatal,
            component: "SamplingService",
            operation: "read",
            retryCount: codeSuffix,
            sourceID: nil,
            underlyingCode: "transport_error"
        ),
        sessionID: try! SessionID(validating: "00000000-0000-4000-8000-000000000801"),
        appVersion: "0.1.0-test",
        model: "Mac16,13",
        osBuild: "24G419",
        incompleteShutdownSteps: ["await_worker_exit"],
        writtenAt: Date()
    )
}

private func logFiles(in directory: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasPrefix("diagnostic-") && $0.pathExtension == "jsonl" }
}

private func reportFiles(in directory: URL) throws -> [URL] {
    let reportsDirectory = directory.appendingPathComponent("reports", isDirectory: true)
    guard FileManager.default.fileExists(atPath: reportsDirectory.path) else {
        return []
    }
    return try FileManager.default.contentsOfDirectory(at: reportsDirectory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }
}
