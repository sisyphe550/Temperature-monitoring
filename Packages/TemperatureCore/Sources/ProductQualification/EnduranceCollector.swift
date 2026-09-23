import Darwin
import Foundation
import SensorRuntime
import TemperatureCore

struct EnduranceReport: Encodable {
    struct Checkpoint: Encodable {
        let hour: Int
        let elapsedSeconds: Double
        let committedBatches: Int
        let committedBatchesDelta: Int
        let cpuRawSamples: Int
        let cpuRawSamplesDelta: Int
        let gaps: Int
        let databaseBytes: Int
        let walBytes: Int
        let shmBytes: Int
        let queueTotalRecords: Int
        let queueAcceptsNewReservations: Bool
        let rawSampleRows: Int
        let emaSampleRows: Int
        let aggregateRows: Int
        let aggregate1sRows: Int
        let aggregate10sRows: Int
        let aggregate1mRows: Int
    }

    let artifactKind = "product-hardware-endurance"
    let schemaVersion = 1
    let recordedAt: String
    let plannedDurationSeconds: Int
    let actualDurationSeconds: Double
    let checkpointIntervalSeconds: Int
    let cpuPeriodMS: Int
    let crossedTTLSeconds: Int
    let checkpoints: [Checkpoint]
    let mappingAndFreshness = "not inferred from variation or repeated values"
}

enum EnduranceCollector {
    private static let maxTTLSeconds = 259_200

    static func collect(
        workerURL: URL,
        profileURL: URL,
        defaultsURL: URL?,
        durationSeconds: Int,
        checkpointIntervalSeconds: Int,
        outputDirectory: URL
    ) async throws -> EnduranceReport {
        let profile = try Configuration.loadProfile(from: profileURL)
        try SourcesCollector.assertHostModel(profile: profile)
        guard let defaultsURL else {
            throw QualificationError.missingArgument("--defaults")
        }
        guard checkpointIntervalSeconds > 0 else {
            throw QualificationError.invalidValue("--checkpoint-interval-seconds")
        }
        let configuration = try Configuration.load(from: defaultsURL)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let databaseURL = outputDirectory.appendingPathComponent("endurance.sqlite")
        let checkpointLogURL = outputDirectory.appendingPathComponent("endurance-checkpoints.jsonl")

        let transport = WorkerClient(
            configuration: WorkerClientConfiguration(
                executableURL: workerURL,
                timeouts: WorkerClientTimeouts(
                    readDeadlineMS: 30_000,
                    discoverDeadlineMS: 10_000,
                    terminateGraceMS: 250
                )
            )
        )
        let client = QualifiedSensorClient(
            transport: transport,
            registry: ProfileRegistry(profile: profile)
        )
        let session = SessionPersistenceActor(databaseURL: databaseURL)
        let controller = SessionMonitorController(
            clock: SystemClock(),
            client: client,
            session: session,
            sessionMetadata: try sessionMetadata(profile: profile),
            configuration: configuration
        )

        let cpuPeriodMS = configuration.cpuDefaultMS
        let started = Date()
        try await controller.start()
        try await controller.setCPUPeriod(milliseconds: cpuPeriodMS)
        let snapshotStream = await controller.snapshots()
        let snapshotSink = Task {
            for await _ in snapshotStream {
                if Task.isCancelled {
                    break
                }
            }
        }
        defer {
            snapshotSink.cancel()
        }

        var checkpoints: [EnduranceReport.Checkpoint] = []
        var previousBatches = 0
        var previousRawSamples = 0
        let checkpointCount = max(1, Int(ceil(Double(durationSeconds) / Double(checkpointIntervalSeconds))))
        for index in 1...checkpointCount {
            let targetElapsed = min(index * checkpointIntervalSeconds, durationSeconds)
            let remaining = targetElapsed - Int(Date().timeIntervalSince(started))
            if remaining > 0 {
                for _ in 0..<remaining {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            await controller.waitForPersistenceDrain(maxSeconds: 30)
            let queue = await controller.persistenceQueueSnapshot()
            let evidence = try SQLiteEvidence.endurance(databaseURL: databaseURL)
            let footprint = databaseFootprint(at: databaseURL)
            let checkpoint = EnduranceReport.Checkpoint(
                hour: index,
                elapsedSeconds: Date().timeIntervalSince(started),
                committedBatches: evidence.committedBatches,
                committedBatchesDelta: evidence.committedBatches - previousBatches,
                cpuRawSamples: evidence.cpuRawSamples,
                cpuRawSamplesDelta: evidence.cpuRawSamples - previousRawSamples,
                gaps: evidence.gaps,
                databaseBytes: footprint.database,
                walBytes: footprint.wal,
                shmBytes: footprint.shm,
                queueTotalRecords: queue.totalRecords,
                queueAcceptsNewReservations: queue.acceptsNewReservations,
                rawSampleRows: evidence.rawSampleRows,
                emaSampleRows: evidence.emaSampleRows,
                aggregateRows: evidence.aggregateRows,
                aggregate1sRows: evidence.aggregate1sRows,
                aggregate10sRows: evidence.aggregate10sRows,
                aggregate1mRows: evidence.aggregate1mRows
            )
            previousBatches = evidence.committedBatches
            previousRawSamples = evidence.cpuRawSamples
            checkpoints.append(checkpoint)
            try appendCheckpoint(checkpoint, to: checkpointLogURL)
        }

        let stats = await controller.samplingStatistics()
        let acceptFailure = await controller.lastAcceptFailure()
        await controller.stop()
        await transport.close()

        let actualDuration = Date().timeIntervalSince(started)
        guard let last = checkpoints.last, last.committedBatches > 0 else {
            let failureCode = acceptFailure?.code.rawValue ?? "none"
            let underlying = acceptFailure?.underlyingCode ?? "none"
            throw QualificationError.invalidValue(
                "endurance produced no committed batches; completedReads=\(stats.completedReads) "
                    + "acceptFailure=\(failureCode)/\(underlying)"
            )
        }

        return EnduranceReport(
            recordedAt: ISO8601DateFormatter().string(from: Date()),
            plannedDurationSeconds: durationSeconds,
            actualDurationSeconds: actualDuration,
            checkpointIntervalSeconds: checkpointIntervalSeconds,
            cpuPeriodMS: cpuPeriodMS,
            crossedTTLSeconds: maxTTLSeconds,
            checkpoints: checkpoints
        )
    }

    private static func appendCheckpoint(
        _ checkpoint: EnduranceReport.Checkpoint,
        to url: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(checkpoint)
        data.append(Data("\n".utf8))
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url)
        }
    }

    private static func databaseFootprint(at url: URL) -> (database: Int, wal: Int, shm: Int) {
        let fileManager = FileManager.default
        func size(at path: String) -> Int {
            guard let attributes = try? fileManager.attributesOfItem(atPath: path),
                  let bytes = attributes[.size] as? NSNumber else {
                return 0
            }
            return bytes.intValue
        }
        return (
            database: size(at: url.path),
            wal: size(at: url.path + "-wal"),
            shm: size(at: url.path + "-shm")
        )
    }

    private static func sessionMetadata(profile: SensorProfile) throws -> SessionMetadata {
        let build = ProcessInfo.processInfo.operatingSystemVersionString
        return SessionMetadata(
            sessionID: try SessionID(validating: UUID().uuidString.lowercased()),
            startedWallUnixNS: Int64(Date().timeIntervalSince1970 * 1_000_000_000),
            model: profile.model,
            osBuild: build,
            appVersion: "product-qualification"
        )
    }
}
