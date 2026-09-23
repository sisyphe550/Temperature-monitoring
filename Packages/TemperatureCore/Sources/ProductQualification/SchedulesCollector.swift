import Darwin
import Foundation
import SensorRuntime
import TemperatureCore

struct SchedulesReport: Encodable {
    struct Phase: Encodable {
        let cpuPeriodMS: Int
        let plannedDurationSeconds: Int
        let actualDurationSeconds: Double
        let committedBatches: Int
        let cpuRawSamples: Int
        let expectedOpportunities: Int
        let missedOpportunities: Int
        let gaps: Int
        let mappingAndFreshness: String
    }

    let artifactKind = "product-hardware-schedules"
    let schemaVersion = 1
    let recordedAt: String
    let durationSeconds: Int
    let intervalsMS: [Int]
    let phases: [Phase]
}

enum SchedulesCollector {
    static func collect(
        workerURL: URL,
        profileURL: URL,
        defaultsURL: URL?,
        durationSeconds: Int,
        intervalsMS: [Int],
        outputDirectory: URL
    ) async throws -> SchedulesReport {
        let profile = try Configuration.loadProfile(from: profileURL)
        try SourcesCollector.assertHostModel(profile: profile)
        guard let defaultsURL else {
            throw QualificationError.missingArgument("--defaults")
        }
        let configuration = try Configuration.load(from: defaultsURL)
        let expectedIntervals = Set(configuration.cpuIntervalsMS)
        guard Set(intervalsMS).isSubset(of: expectedIntervals) else {
            throw QualificationError.invalidValue("--intervals")
        }

        var phases: [SchedulesReport.Phase] = []
        for interval in intervalsMS {
            let phase = try await runPhase(
                workerURL: workerURL,
                profile: profile,
                configuration: configuration,
                cpuPeriodMS: interval,
                durationSeconds: durationSeconds,
                outputDirectory: outputDirectory
            )
            phases.append(phase)
        }

        return SchedulesReport(
            recordedAt: ISO8601DateFormatter().string(from: Date()),
            durationSeconds: durationSeconds,
            intervalsMS: intervalsMS,
            phases: phases
        )
    }

    private static func runPhase(
        workerURL: URL,
        profile: SensorProfile,
        configuration: RuntimeConfiguration,
        cpuPeriodMS: Int,
        durationSeconds: Int,
        outputDirectory: URL
    ) async throws -> SchedulesReport.Phase {
        let phaseDirectory = outputDirectory.appendingPathComponent("phase-\(cpuPeriodMS)ms", isDirectory: true)
        try FileManager.default.createDirectory(at: phaseDirectory, withIntermediateDirectories: true)
        let databaseURL = phaseDirectory.appendingPathComponent("monitor.sqlite")

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
        for _ in 0..<durationSeconds {
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        let stats = await controller.samplingStatistics()
        let acceptFailure = await controller.lastAcceptFailure()
        let evidence = try SQLiteEvidence.read(databaseURL: databaseURL, periodMS: cpuPeriodMS)
        let actualDuration = Date().timeIntervalSince(started)
        let expected = max(0, Int((Double(durationSeconds) * 1000.0) / Double(cpuPeriodMS)))
        let startedBatches = evidence.committedBatches
        let missed = max(0, expected - startedBatches)

        await controller.stop()
        await transport.close()

        if evidence.committedBatches == 0 {
            let failureCode = acceptFailure?.code.rawValue ?? "none"
            let underlying = acceptFailure?.underlyingCode ?? "none"
            let skipped = stats.skippedByKind
                .map { "\($0.key)=\($0.value)" }
                .sorted()
                .joined(separator: ",")
            throw QualificationError.invalidValue(
                "schedule phase \(cpuPeriodMS)ms produced no committed batches; "
                    + "completedReads=\(stats.completedReads) skipped={\(skipped)} "
                    + "acceptFailure=\(failureCode)/\(underlying)"
            )
        }

        try FileManager.default.removeItem(at: phaseDirectory)

        return SchedulesReport.Phase(
            cpuPeriodMS: cpuPeriodMS,
            plannedDurationSeconds: durationSeconds,
            actualDurationSeconds: actualDuration,
            committedBatches: startedBatches,
            cpuRawSamples: evidence.cpuRawSamples,
            expectedOpportunities: expected,
            missedOpportunities: missed,
            gaps: evidence.gaps,
            mappingAndFreshness: "not inferred from variation or repeated values"
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

extension SourcesCollector {
    static func assertHostModel(profile: SensorProfile) throws {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let hostModel = String(cString: model)
        guard hostModel == profile.model else {
            throw QualificationError.hostModelMismatch(expected: profile.model, actual: hostModel)
        }
    }
}
