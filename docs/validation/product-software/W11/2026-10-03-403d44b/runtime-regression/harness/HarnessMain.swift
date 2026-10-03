import Foundation
import TemperatureCore
import SensorRuntime
import TemperaturePresentation

actor StartupGateClient: SensorClient {
    let catalog: QualifiedSourceCatalog
    var didEnterDiscover = false
    var gate: CheckedContinuation<Void, Never>?
    var released = false
    var discoverCount = 0
    var holdWake = false
    var wakeEntered = false
    var wakeGate: CheckedContinuation<Void, Error>?
    init(catalog: QualifiedSourceCatalog) { self.catalog = catalog }
    func discover() async throws -> QualifiedSourceCatalog {
        discoverCount += 1
        if holdWake && discoverCount >= 2 {
            wakeEntered = true
            try await withCheckedThrowingContinuation { wakeGate = $0 }
        }
        if !released {
            didEnterDiscover = true
            await withCheckedContinuation { gate = $0 }
        }
        return catalog
    }
    func release() { released = true; gate?.resume(); gate = nil }
    func holdNextWake() { holdWake = true }
    func cancelWake() { wakeGate?.resume(throwing: CancellationError()); wakeGate = nil }
    func read(_ request: ReadRequest) async throws -> ReadBatch { throw CancellationError() }
    func close() async {}
}

@main
struct HarnessMain {
    @MainActor
    static func main() async throws {
        let scenario = CommandLine.arguments.dropFirst().first ?? "immediate"
        let configuration = try Configuration.bundledDefaults()
        let profile = try Configuration.bundledProfile()
        let catalog = try ProfileRegistry(profile: profile).qualify(DiscoveredCatalog(generation: 1, sources: profile.cpuKeys.map { key in
            DiscoveredSource(transportHandle: "mock:" + key, provider: .smc, rawKey: key, registryID: "reg:" + key, encoding: profile.expectedSMCEncoding, byteCount: profile.expectedSMCSizeBytes)
        }))
        let client = StartupGateClient(catalog: catalog)
        let clock = TestClock(now: Timestamp(elapsedNS: 0, wallUnixNS: 1_800_000_000_000_000_000))
        let support = URL(fileURLWithPath: "/tmp/temperature-runtime-final-review/Sessions-" + UUID().uuidString)
        let coordinator = SessionCoordinator(clock: clock, client: client, configuration: configuration, applicationSupportBase: support)
        let metric = try MetricID(validating: "cpu.zone.max")
        let model = PresentationModel(primaryCPUMetricID: metric)
        let runtime = AppSessionRuntime(presentationModel: model, coordinator: coordinator, clock: clock, configuration: configuration, profile: profile, primaryCPUMetricID: metric)
        var fatalCode: String?
        runtime.setFatalHandler { fatalCode = $0.failure.code.rawValue }
        let start = ProcessInfo.processInfo.systemUptime
        func emit(_ event: String, _ fields: [String: Any] = [:]) {
            var item=fields
            item["event"]=event; item["scenario"]=scenario; item["awake_seconds"]=ProcessInfo.processInfo.systemUptime-start
            FileHandle.standardOutput.write(try! JSONSerialization.data(withJSONObject: item, options: [.sortedKeys]))
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
        runtime.start()
        let sleepTask: Task<Void, Never>
        if scenario == "stop-before-admission" || scenario == "stop-discover-held" {
            if scenario == "stop-discover-held" {
                while !(await client.didEnterDiscover) { await Task.yield() }
            }
            let release = Task {
                try? await Task.sleep(for: .milliseconds(50))
                await client.release()
            }
            await runtime.stop()
            await release.value
            let sessionsRoot = support.appendingPathComponent(configuration.bundleID + "/Sessions")
            let remaining = (try? FileManager.default.contentsOfDirectory(atPath: sessionsRoot.path)) ?? []
            let request = HistoryRequest(seriesIDs: [try SeriesID(validating: "00000000-0000-4000-8000-000000000200")], range: .fiveMinutes, asOfElapsedNS: 0, pointLimit: 100)
            var rejectsStopped = false
            do { _ = try await coordinator.queryHistory(request) }
            catch SessionCoordinatorError.notRunning { rejectsStopped = true }
            catch { emit("unexpected_stopped_query_error", ["error": String(describing: error)]) }
            emit("startup_stop_conclusion", ["remaining_session_directories": remaining, "rejects_stopped": rejectsStopped, "fatal_code": fatalCode ?? ""])
            exit(remaining.isEmpty && rejectsStopped && fatalCode == nil ? 0 : 1)
        } else if scenario == "same-mainactor-job" {
            // Direct synchronous call before the newly created run/start Task can execute.
            let release = Task {
                try? await Task.sleep(for: .milliseconds(50))
                emit("release_startup_discovery")
                await client.release()
            }
            await runtime.suspendForSleep()
            await release.value
            sleepTask = Task {}
        } else if scenario == "immediate" {
            // The same MainActor job calls sleep before run() can execute its first step.
            sleepTask = Task { await runtime.suspendForSleep() }
        } else {
            while !(await client.didEnterDiscover) { await Task.yield() }
            sleepTask = Task { await runtime.suspendForSleep() }
        }
        // Run the queued sleep while startup discovery is explicitly held.
        for _ in 0..<100 { await Task.yield() }
        emit("release_startup_discovery")
        await client.release()
        await sleepTask.value
        for _ in 0..<100 { await Task.yield() }
        let seriesID = try SeriesID(validating: "00000000-0000-4000-8000-000000000200")
        let request = HistoryRequest(seriesIDs: [seriesID], range: .fiveMinutes, asOfElapsedNS: 0, pointLimit: 100)
        var cancelled=false
        do { _=try await coordinator.queryHistory(request) }
        catch is CancellationError { cancelled=true }
        catch { emit("unexpected_query_error", ["error":String(describing:error)]) }
        emit("startup_sleep_conclusion", ["history_cancelled_as_suspended":cancelled,"fatal_code":fatalCode ?? ""])
        let passed=cancelled && fatalCode == nil
        if scenario == "stop-cancelled-wake" {
            await client.holdNextWake()
            let wake = Task { await runtime.resumeAfterWake() }
            while !(await client.wakeEntered) { await Task.yield() }
            wake.cancel()
            let stop = Task { await runtime.stop() }
            for _ in 0..<100 { await Task.yield() }
            await client.cancelWake()
            await wake.value
            await stop.value
            emit("stop_cancelled_wake_conclusion", ["fatal_code": fatalCode ?? ""])
            exit(fatalCode == nil ? 0 : 1)
        }
        await runtime.resumeAfterWake()
        var resumed=false
        do { _=try await coordinator.queryHistory(request); resumed=true }
        catch { emit("unexpected_wake_query_error", ["error":String(describing:error)]) }
        emit("wake_conclusion", ["history_resumed":resumed,"fatal_code":fatalCode ?? ""])
        await runtime.stop()
        emit("normal_stop")
        exit(passed && resumed && fatalCode == nil ? 0 : 1)
    }
}
