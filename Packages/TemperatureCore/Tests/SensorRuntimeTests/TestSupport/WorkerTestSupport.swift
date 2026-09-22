import Foundation
@testable import SensorRuntime

enum WorkerTestSupport {
    static func protocolWorkerURL() throws -> URL {
        let packageRoot = try locatePackageRoot()

        let buildRoot = packageRoot.appendingPathComponent(".build")
        let candidates = (try? FileManager.default.contentsOfDirectory(at: buildRoot, includingPropertiesForKeys: nil))?
            .filter {
                $0.hasDirectoryPath
                    && ($0.lastPathComponent.hasPrefix("arm64") || $0.lastPathComponent.hasPrefix("x86"))
            }
            .map { $0.appendingPathComponent("debug/ProtocolWorker") }
            .filter { FileManager.default.fileExists(atPath: $0.path) } ?? []

        if let url = candidates.first {
            return url
        }

        throw WorkerTestSupportError.protocolWorkerNotBuilt(
            """
            ProtocolWorker is not built. Run:
            swift build --package-path \(packageRoot.path) --product ProtocolWorker
            """
        )
    }

    private static func locatePackageRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw WorkerTestSupportError.protocolWorkerNotBuilt("Could not locate Package.swift from test support")
    }

    static func client(
        scenario: String,
        timeouts: WorkerClientTimeouts = .production
    ) throws -> WorkerClient {
        WorkerClient(
            configuration: WorkerClientConfiguration(
                executableURL: try protocolWorkerURL(),
                environment: ["WORKER_SCENARIO": scenario],
                timeouts: timeouts
            )
        )
    }

    static let fastTimeouts = WorkerClientTimeouts(
        readDeadlineMS: 150,
        discoverDeadlineMS: 200,
        terminateGraceMS: 50
    )
}

enum WorkerTestSupportError: Error, CustomStringConvertible {
    case protocolWorkerNotBuilt(String)

    var description: String {
        switch self {
        case .protocolWorkerNotBuilt(let message):
            return message
        }
    }
}
