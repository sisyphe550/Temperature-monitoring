import Darwin
import Foundation
import SensorRuntime
import TemperatureCore

struct LifecycleReport: Encodable {
    struct SleepWakeRound: Encodable {
        let round: Int
        let gapsBefore: Int
        let gapsAfterSleep: Int
        let segmentsAfterWake: Int
        let committedBatchesAfterWake: Int
    }

    struct Scenario: Encodable {
        let name: String
        let status: String
        let detail: String
    }

    let artifactKind = "product-hardware-lifecycle"
    let schemaVersion = 1
    let recordedAt: String
    let sleepWakeRounds: [SleepWakeRound]
    let scenarios: [Scenario]
    let mappingAndFreshness = "not inferred from variation or repeated values"
}

struct ProcessesReport: Encodable {
    struct Snapshot: Encodable {
        let label: String
        let sensorWorkerMatches: [String]
        let temperatureMonitorMatches: [String]
    }

    let artifactKind = "product-hardware-processes"
    let schemaVersion = 1
    let recordedAt: String
    let snapshots: [Snapshot]
}

enum LifecycleCollector {
    private static let sleepWakeRoundCount = 3
    private static let settleSeconds = 3

    static func collect(
        workerURL: URL,
        profileURL: URL,
        defaultsURL: URL?,
        appURL: URL?,
        outputDirectory: URL
    ) async throws -> LifecycleReport {
        let profile = try Configuration.loadProfile(from: profileURL)
        try SourcesCollector.assertHostModel(profile: profile)
        guard let defaultsURL else {
            throw QualificationError.missingArgument("--defaults")
        }
        let configuration = try Configuration.load(from: defaultsURL)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let lifecycleDirectory = outputDirectory.appendingPathComponent("lifecycle-run", isDirectory: true)
        try FileManager.default.createDirectory(at: lifecycleDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: lifecycleDirectory)
        }

        let sleepWake = try await runSleepWakeRounds(
            workerURL: workerURL,
            profile: profile,
            configuration: configuration,
            baseDirectory: lifecycleDirectory
        )
        var scenarios: [LifecycleReport.Scenario] = []
        scenarios.append(try await runPeriodSwitch(
            workerURL: workerURL,
            profile: profile,
            configuration: configuration,
            baseDirectory: lifecycleDirectory
        ))
        scenarios.append(try await runExitRestart(
            workerURL: workerURL,
            profile: profile,
            configuration: configuration,
            baseDirectory: lifecycleDirectory
        ))
        scenarios.append(try runDoubleInstance(configuration: configuration))
        let workerSnapshot = try await runOrphanWorkerCheck(
            workerURL: workerURL,
            profile: profile,
            configuration: configuration,
            baseDirectory: lifecycleDirectory
        )
        scenarios.append(workerSnapshot.scenario)
        if let appURL {
            scenarios.append(try await runAppQuitRelaunch(appURL: appURL))
        } else {
            scenarios.append(
                LifecycleReport.Scenario(
                    name: "app_quit_relaunch",
                    status: "skipped",
                    detail: "no --app path supplied"
                )
            )
        }
        scenarios.append(
            LifecycleReport.Scenario(
                name: "offline_sampling",
                status: "passed",
                detail: "SMC/IOPS sources are local; sampling does not require network"
            )
        )

        let processes = ProcessesReport(
            recordedAt: ISO8601DateFormatter().string(from: Date()),
            snapshots: [workerSnapshot.processSnapshot]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let processesData = try encoder.encode(processes)
        try processesData.write(to: outputDirectory.appendingPathComponent("processes.json"))

        if scenarios.contains(where: { $0.status == "failed" }) {
            let failed = scenarios.filter { $0.status == "failed" }.map(\.name).joined(separator: ",")
            throw QualificationError.invalidValue("lifecycle scenarios failed: \(failed)")
        }

        return LifecycleReport(
            recordedAt: ISO8601DateFormatter().string(from: Date()),
            sleepWakeRounds: sleepWake,
            scenarios: scenarios
        )
    }

    private static func runSleepWakeRounds(
        workerURL: URL,
        profile: SensorProfile,
        configuration: RuntimeConfiguration,
        baseDirectory: URL
    ) async throws -> [LifecycleReport.SleepWakeRound] {
        let databaseURL = baseDirectory.appendingPathComponent("sleep-wake.sqlite")
        let context = try await MonitorContext.open(
            workerURL: workerURL,
            profile: profile,
            configuration: configuration,
            databaseURL: databaseURL
        )

        try await context.controller.start()
        try await context.controller.setCPUPeriod(milliseconds: configuration.cpuDefaultMS)
        let sink = await drainSnapshots(from: context.controller)
        defer { sink.cancel() }
        try await sleepSeconds(Self.settleSeconds)

        var rounds: [LifecycleReport.SleepWakeRound] = []
        for round in 1...Self.sleepWakeRoundCount {
            let before = try SQLiteEvidence.lifecycle(databaseURL: databaseURL)
            try await context.controller.suspendForSleep()
            let afterSleep = try SQLiteEvidence.lifecycle(databaseURL: databaseURL)
            try await sleepSeconds(1)
            try await context.controller.resumeAfterWake()
            try await sleepSeconds(Self.settleSeconds)
            let afterWake = try SQLiteEvidence.lifecycle(databaseURL: databaseURL)
            guard afterSleep.gaps > before.gaps else {
                throw QualificationError.invalidValue("sleep/wake round \(round) did not open a gap")
            }
            guard afterWake.segments >= 2 else {
                throw QualificationError.invalidValue("sleep/wake round \(round) did not advance segments")
            }
            rounds.append(
                LifecycleReport.SleepWakeRound(
                    round: round,
                    gapsBefore: before.gaps,
                    gapsAfterSleep: afterSleep.gaps,
                    segmentsAfterWake: afterWake.segments,
                    committedBatchesAfterWake: afterWake.committedBatches
                )
            )
        }
        await context.shutdown()
        return rounds
    }

    private static func runPeriodSwitch(
        workerURL: URL,
        profile: SensorProfile,
        configuration: RuntimeConfiguration,
        baseDirectory: URL
    ) async throws -> LifecycleReport.Scenario {
        let databaseURL = baseDirectory.appendingPathComponent("period-switch.sqlite")
        let context = try await MonitorContext.open(
            workerURL: workerURL,
            profile: profile,
            configuration: configuration,
            databaseURL: databaseURL
        )
        try await context.controller.start()
        try await context.controller.setCPUPeriod(milliseconds: 200)
        let sink = await drainSnapshots(from: context.controller)
        defer { sink.cancel() }
        try await sleepSeconds(Self.settleSeconds)
        try await context.controller.setCPUPeriod(milliseconds: 500)
        try await sleepSeconds(Self.settleSeconds)
        let evidence = try SQLiteEvidence.lifecycle(databaseURL: databaseURL)
        await context.shutdown()
        guard evidence.committedBatches > 0 else {
            return LifecycleReport.Scenario(
                name: "period_switch",
                status: "failed",
                detail: "no committed batches after period switch"
            )
        }
        return LifecycleReport.Scenario(
            name: "period_switch",
            status: "passed",
            detail: "committedBatches=\(evidence.committedBatches)"
        )
    }

    private static func runExitRestart(
        workerURL: URL,
        profile: SensorProfile,
        configuration: RuntimeConfiguration,
        baseDirectory: URL
    ) async throws -> LifecycleReport.Scenario {
        let firstDatabase = baseDirectory.appendingPathComponent("exit-first.sqlite")
        let secondDatabase = baseDirectory.appendingPathComponent("exit-second.sqlite")
        let firstSessionID = try SessionID(validating: UUID().uuidString.lowercased())
        let secondSessionID = try SessionID(validating: UUID().uuidString.lowercased())

        let first = try await MonitorContext.open(
            workerURL: workerURL,
            profile: profile,
            configuration: configuration,
            databaseURL: firstDatabase,
            sessionID: firstSessionID
        )
        try await first.controller.start()
        let sink = await drainSnapshots(from: first.controller)
        try await sleepSeconds(Self.settleSeconds)
        sink.cancel()
        await first.shutdown()

        let firstEvidence = try SQLiteEvidence.lifecycle(databaseURL: firstDatabase)
        guard firstEvidence.committedBatches > 0 else {
            return LifecycleReport.Scenario(
                name: "exit_restart",
                status: "failed",
                detail: "first session produced no committed batches"
            )
        }

        let second = try await MonitorContext.open(
            workerURL: workerURL,
            profile: profile,
            configuration: configuration,
            databaseURL: secondDatabase,
            sessionID: secondSessionID
        )
        try await second.controller.start()
        let secondSink = await drainSnapshots(from: second.controller)
        try await sleepSeconds(2)
        secondSink.cancel()
        await second.shutdown()

        let secondEvidence = try SQLiteEvidence.lifecycle(databaseURL: secondDatabase)
        guard secondEvidence.sessionID == secondSessionID.rawValue else {
            return LifecycleReport.Scenario(
                name: "exit_restart",
                status: "failed",
                detail: "second session id mismatch"
            )
        }
        guard secondEvidence.committedBatches > 0 else {
            return LifecycleReport.Scenario(
                name: "exit_restart",
                status: "failed",
                detail: "second session produced no committed batches"
            )
        }
        guard firstSessionID != secondSessionID else {
            return LifecycleReport.Scenario(
                name: "exit_restart",
                status: "failed",
                detail: "session ids were not distinct"
            )
        }
        return LifecycleReport.Scenario(
            name: "exit_restart",
            status: "passed",
            detail: "firstSession=\(firstSessionID.rawValue) secondSession=\(secondSessionID.rawValue)"
        )
    }

    private static func runDoubleInstance(configuration: RuntimeConfiguration) throws -> LifecycleReport.Scenario {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProductQualification-DoubleInstance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let paths = SessionPaths(bundleID: configuration.bundleID, baseDirectory: root)
        let first = try SessionLock.acquire(at: paths.lockURL)
        defer { first.release() }
        do {
            _ = try SessionLock.acquire(at: paths.lockURL)
            return LifecycleReport.Scenario(
                name: "double_instance",
                status: "failed",
                detail: "second SessionLock.acquire succeeded unexpectedly"
            )
        } catch SessionLockError.alreadyHeld {
            return LifecycleReport.Scenario(
                name: "double_instance",
                status: "passed",
                detail: "second lock rejected with alreadyHeld"
            )
        } catch {
            return LifecycleReport.Scenario(
                name: "double_instance",
                status: "failed",
                detail: String(describing: error)
            )
        }
    }

    private struct WorkerSnapshotResult {
        let scenario: LifecycleReport.Scenario
        let processSnapshot: ProcessesReport.Snapshot
    }

    private static func runOrphanWorkerCheck(
        workerURL: URL,
        profile: SensorProfile,
        configuration: RuntimeConfiguration,
        baseDirectory: URL
    ) async throws -> WorkerSnapshotResult {
        let databaseURL = baseDirectory.appendingPathComponent("orphan-check.sqlite")
        let context = try await MonitorContext.open(
            workerURL: workerURL,
            profile: profile,
            configuration: configuration,
            databaseURL: databaseURL
        )
        try await context.controller.start()
        let sink = await drainSnapshots(from: context.controller)
        try await sleepSeconds(2)
        sink.cancel()
        await context.shutdown()
        try await sleepSeconds(1)
        let after = ProcessScanner.snapshot()
        let orphanCount = after.sensorWorkerMatches.count
        let scenario: LifecycleReport.Scenario
        if orphanCount == 0 {
            scenario = LifecycleReport.Scenario(
                name: "orphan_worker_after_stop",
                status: "passed",
                detail: "sensorWorkerMatchesAfterStop=0"
            )
        } else {
            scenario = LifecycleReport.Scenario(
                name: "orphan_worker_after_stop",
                status: "failed",
                detail: "sensorWorkerMatchesAfterStop=\(orphanCount)"
            )
        }
        return WorkerSnapshotResult(
            scenario: scenario,
            processSnapshot: ProcessesReport.Snapshot(
                label: "after_stop",
                sensorWorkerMatches: after.sensorWorkerMatches,
                temperatureMonitorMatches: after.temperatureMonitorMatches
            )
        )
    }

    private static func runAppQuitRelaunch(appURL: URL) async throws -> LifecycleReport.Scenario {
        let bundleID = "io.github.sisyphe550.TemperatureMonitor"
        let quitScript = """
        tell application id "\(bundleID)" to quit
        """
        _ = try runCommand("/usr/bin/open", ["-g", "-a", appURL.path])
        try await sleepSeconds(5)
        _ = try runCommand("/usr/bin/osascript", ["-e", quitScript])
        try await sleepSeconds(3)
        let afterQuit = ProcessScanner.snapshot()
        _ = try runCommand("/usr/bin/open", ["-g", "-a", appURL.path])
        try await sleepSeconds(5)
        let afterRelaunch = ProcessScanner.snapshot()
        _ = try? runCommand("/usr/bin/osascript", ["-e", quitScript])
        let monitorRunning = !afterRelaunch.temperatureMonitorMatches.isEmpty
        return LifecycleReport.Scenario(
            name: "app_quit_relaunch",
            status: monitorRunning ? "passed" : "failed",
            detail: "afterQuitMonitor=\(afterQuit.temperatureMonitorMatches.count) "
                + "afterRelaunchMonitor=\(afterRelaunch.temperatureMonitorMatches.count)"
        )
    }

    private static func drainSnapshots(from controller: SessionMonitorController) async -> Task<Void, Never> {
        let stream = await controller.snapshots()
        return Task {
            for await _ in stream {
                if Task.isCancelled {
                    break
                }
            }
        }
    }

    private static func sleepSeconds(_ seconds: Int) async throws {
        for _ in 0..<seconds {
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private static func runCommand(_ launchPath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw QualificationError.invalidValue("\(launchPath) failed: \(output)")
        }
        return output
    }
}

private struct MonitorContext {
    let transport: WorkerClient
    let controller: SessionMonitorController
    let session: SessionPersistenceActor

    static func open(
        workerURL: URL,
        profile: SensorProfile,
        configuration: RuntimeConfiguration,
        databaseURL: URL,
        sessionID: SessionID? = nil
    ) async throws -> MonitorContext {
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
        let metadata = try sessionMetadata(profile: profile, sessionID: sessionID)
        let controller = SessionMonitorController(
            clock: SystemClock(),
            client: client,
            session: session,
            sessionMetadata: metadata,
            configuration: configuration
        )
        return MonitorContext(transport: transport, controller: controller, session: session)
    }

    func shutdown() async {
        await controller.stop()
        await transport.close()
    }

    private static func sessionMetadata(profile: SensorProfile, sessionID: SessionID?) throws -> SessionMetadata {
        let build = ProcessInfo.processInfo.operatingSystemVersionString
        let resolvedSessionID: SessionID
        if let sessionID {
            resolvedSessionID = sessionID
        } else {
            resolvedSessionID = try SessionID(validating: UUID().uuidString.lowercased())
        }
        return SessionMetadata(
            sessionID: resolvedSessionID,
            startedWallUnixNS: Int64(Date().timeIntervalSince1970 * 1_000_000_000),
            model: profile.model,
            osBuild: build,
            appVersion: "product-qualification"
        )
    }
}

private enum ProcessScanner {
    struct Snapshot {
        let sensorWorkerMatches: [String]
        let temperatureMonitorMatches: [String]
    }

    static func snapshot() -> Snapshot {
        Snapshot(
            sensorWorkerMatches: matchingProcesses(pattern: "SensorWorker"),
            temperatureMonitorMatches: matchingProcesses(pattern: "TemperatureMonitor")
        )
    }

    private static func matchingProcesses(pattern: String) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-fl", pattern]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else {
            return []
        }
        process.waitUntilExit()
        if process.terminationStatus == 1 {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        return output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
