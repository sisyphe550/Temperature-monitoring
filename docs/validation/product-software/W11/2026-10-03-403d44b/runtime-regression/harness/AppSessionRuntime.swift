import Foundation
import Darwin
import SensorRuntime
import TemperatureCore
import TemperaturePresentation

enum AppSessionError: Error, Sendable {
    case missingSensorWorker
    case startupFailed(String)
}

@MainActor
final class AppSessionRuntime {
    private enum HistoryLifecycleState { case inactive, starting, active, suspended }

    private let presentationModel: PresentationModel
    private let clock: MonitorClock
    private let coordinator: SessionCoordinator
    private let configuration: RuntimeConfiguration
    private let profile: SensorProfile
    private let primaryCPUMetricID: MetricID
    private var snapshotTask: Task<Void, Never>?
    private var startupTask: Task<Void, Error>?
    private var historyTask: Task<Void, Never>?
    private var historyRequestOrdinal: UInt64 = 0
    private var historyLifecycleState: HistoryLifecycleState = .inactive
    private var lastHistoryRefreshElapsedNS: Int64?
    private var selectedHistoryRange: HistoryRange = .fiveMinutes
    private var selectedSeriesIDs: [SeriesID] = []
    private var selectedMetricIDs: Set<MetricID> = []
    private var knownDefinitions: [SeriesID: SeriesDefinition] = [:]
    private var lastSeenDefinitionElapsedNS: [SeriesID: Int64] = [:]
    private var fatalHandler: (@MainActor (FatalDisplayReceipt) -> Void)?

    init(
        presentationModel: PresentationModel,
        coordinator: SessionCoordinator,
        clock: MonitorClock,
        configuration: RuntimeConfiguration,
        profile: SensorProfile,
        primaryCPUMetricID: MetricID
    ) {
        self.presentationModel = presentationModel
        self.coordinator = coordinator
        self.clock = clock
        self.configuration = configuration
        self.profile = profile
        self.primaryCPUMetricID = primaryCPUMetricID
        selectedMetricIDs = [primaryCPUMetricID]
    }

    static func makeProduction(
        presentationModel: PresentationModel,
        primaryCPUMetricID: MetricID
    ) throws -> AppSessionRuntime {
        let configuration = try AppBundleConfiguration.loadRuntimeConfiguration()
        let profile = try AppBundleConfiguration.loadProfile()
        var modelSize = 0
        guard sysctlbyname("hw.model", nil, &modelSize, nil, 0) == 0, modelSize > 0 else {
            throw platformFailure("hw_model_query_failed")
        }
        var modelBytes = [CChar](repeating: 0, count: modelSize)
        guard sysctlbyname("hw.model", &modelBytes, &modelSize, nil, 0) == 0 else {
            throw platformFailure("hw_model_query_failed")
        }
        let actualModel = String(cString: modelBytes)
        guard actualModel == profile.model else { throw platformFailure("unconfigured_model:\(actualModel)") }
        let components = configuration.minimumMacos.split(separator: ".").compactMap { Int($0) }
        guard components.count == 3 else { throw ConfigurationError.invalidValue("minimum_macos") }
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: components[0], minorVersion: components[1], patchVersion: components[2])) else {
            throw platformFailure("minimum_macos:\(configuration.minimumMacos)")
        }
        guard let workerURL = Bundle.main.sensorWorkerExecutableURL else {
            throw AppSessionError.missingSensorWorker
        }
        let supportBase = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let clock = SystemClock()
        let transport = WorkerClient(configuration: WorkerClientConfiguration(
            executableURL: workerURL,
            environment: ["TEMPERATURE_MONITOR_ORIGIN_TICKS": String(clock.basis.originTicks)]
        ))
        let client = QualifiedSensorClient(
            transport: transport,
            registry: ProfileRegistry(profile: profile)
        )
        let coordinator = SessionCoordinator(
            clock: clock,
            client: client,
            configuration: configuration,
            applicationSupportBase: supportBase
        )
        return AppSessionRuntime(
            presentationModel: presentationModel,
            coordinator: coordinator,
            clock: clock,
            configuration: configuration,
            profile: profile,
            primaryCPUMetricID: primaryCPUMetricID
        )
    }

    private static func platformFailure(_ reason: String) -> MonitorFailure {
        MonitorFailure(code: .unsupportedPlatform, severity: .fatal, component: "AppSessionRuntime",
            operation: "platform", retryCount: 0, sourceID: nil, underlyingCode: reason)
    }

    func remainingFatalMS(_ receipt: FatalDisplayReceipt) -> Int { receipt.remainingMS(at: clock.now()) }

    func setFatalHandler(_ handler: @escaping @MainActor (FatalDisplayReceipt) -> Void) { fatalHandler = handler }

    var canApplyLiveControls: Bool {
        snapshotTask != nil
    }

    func start() {
        guard snapshotTask == nil else {
            return
        }
        historyLifecycleState = .starting
        let sessionID = SessionID(UUID())
        let now = clock.now()
        let metadata = SessionMetadata(
            sessionID: sessionID,
            startedWallUnixNS: now.wallUnixNS,
            model: profile.model,
            osBuild: ProcessInfo.processInfo.operatingSystemVersionString,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        )
        startupTask = Task { [coordinator] in
            try Task.checkCancellation()
            try await coordinator.start(sessionMetadata: metadata)
        }
        snapshotTask = Task { [weak self] in
            await self?.run()
        }
    }

    func stop() async {
        historyLifecycleState = .inactive
        let startup = startupTask
        startup?.cancel()
        let snapshot = snapshotTask
        snapshotTask?.cancel()
        snapshotTask = nil
        historyTask?.cancel()
        historyTask = nil
        historyRequestOrdinal += 1
        // Startup may not yet have reached the coordinator's lifecycle queue.
        // Join it before stop so a delayed start cannot create an orphan session.
        _ = await startup?.result
        await coordinator.stop()
        startupTask = nil
        await snapshot?.value
    }

    var shutdownBudgetMS: Int { configuration.shutdownBudgetMS }

    func recordShutdownDeadlineExceeded() async { await coordinator.recordShutdownDeadlineExceeded() }

    func suspendForSleep() async {
        if case .fatal = presentationModel.state { return }
        guard historyLifecycleState == .starting || historyLifecycleState == .active else { return }
        historyLifecycleState = .suspended
        historyRequestOrdinal += 1
        historyTask?.cancel()
        historyTask = nil
        do {
            try await startupTask?.value
            guard historyLifecycleState == .suspended else { return }
            try await coordinator.suspendForSleep()
        } catch {
            guard historyLifecycleState == .suspended, !Task.isCancelled else { return }
            await enterFatal((error as? MonitorFailure) ?? lifecycleFailure(error, operation: "sleep"))
        }
    }

    func resumeAfterWake() async {
        if case .fatal = presentationModel.state { return }
        guard historyLifecycleState == .suspended else { return }
        do {
            try await coordinator.resumeAfterWake()
            guard historyLifecycleState == .suspended else { return }
            historyLifecycleState = .active
            requestHistoryReload(force: true)
        }
        catch {
            guard historyLifecycleState == .suspended, !Task.isCancelled else { return }
            await enterFatal((error as? MonitorFailure) ?? lifecycleFailure(error, operation: "wake"))
        }
    }

    private func lifecycleFailure(_ error: Error, operation: String) -> MonitorFailure {
        MonitorFailure(code: .appInit, severity: .fatal, component: "AppSessionRuntime", operation: operation,
            retryCount: 0, sourceID: nil, underlyingCode: String(describing: error))
    }

    func currentHistoryMetricIDs() -> Set<MetricID> { selectedMetricIDs }

    func setHistoryMetricIDs(_ metrics: Set<MetricID>) {
        guard !metrics.isEmpty, metrics.count <= configuration.historyMaxSeries else { return }
        selectedMetricIDs = metrics
        resolveSelectedSeries(asOfElapsedNS: clock.now().elapsedNS)
        requestHistoryReload(force: true)
    }

    func currentHistoryRange() -> HistoryRange {
        selectedHistoryRange
    }

    func setHistoryRange(_ range: HistoryRange) {
        selectedHistoryRange = range
        resolveSelectedSeries(asOfElapsedNS: clock.now().elapsedNS)
        requestHistoryReload(force: true)
    }

    func setCPUPeriod(milliseconds: Int) async throws {
        try await coordinator.setCPUPeriod(milliseconds: milliseconds)
    }

    private func run() async {
        do {
            guard let startupTask else { return }
            try await startupTask.value
            guard !Task.isCancelled else { return }
            if historyLifecycleState == .starting { historyLifecycleState = .active }
            guard let stream = await coordinator.snapshots() else {
                throw AppSessionError.startupFailed("snapshot stream unavailable")
            }
            for await snapshot in stream {
                if Task.isCancelled {
                    break
                }
                if let failure = await coordinator.lastRuntimeFailure(), failure.severity == .fatal {
                    await enterFatal(failure)
                    return
                }
                presentationModel.apply(snapshot: snapshot)
                updateSelectedSeries(from: snapshot, primaryMetricID: primaryCPUMetricID)
                requestHistoryReload()
            }
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled else { return }
            let failure = (error as? MonitorFailure) ?? MonitorFailure(code: .appInit, severity: .fatal,
                component: "AppSessionRuntime", operation: "start", retryCount: 0, sourceID: nil,
                underlyingCode: String(describing: error))
            await enterFatal(failure)
        }
    }

    private func enterFatal(_ failure: MonitorFailure) async {
        if case .fatal = presentationModel.state { return }
        historyLifecycleState = .inactive
        historyRequestOrdinal += 1
        snapshotTask?.cancel()
        await coordinator.freezeForFatal()
        historyTask?.cancel()
        historyTask = nil
        let receipt = await coordinator.recordFatal(failure, reportPath: nil)
        presentationModel.enterFatal(receipt)
        fatalHandler?(receipt)
    }

    private func requestHistoryReload(force: Bool = false) {
        guard historyLifecycleState == .active else { return }
        if selectedSeriesIDs.isEmpty || selectedSeriesIDs.count > configuration.historyMaxSeries {
            historyTask?.cancel()
            historyTask = nil
            historyRequestOrdinal += 1
            guard !selectedSeriesIDs.isEmpty else { return }
            presentationModel.applyHistoryFailure(MonitorFailure(code: .uiData, severity: .degraded,
                component: "AppSessionRuntime", operation: "historySelection", retryCount: 0, sourceID: nil,
                underlyingCode: "所选范围包含超过8个来源定义，请减少选择或缩短范围；来源变化不能合并为连续曲线"))
            return
        }
        let now = clock.now().elapsedNS
        let refreshNS = selectedHistoryRange == .fiveMinutes
            ? Int64(configuration.uiPublishMS) * 1_000_000 : 1_000_000_000
        if !force {
            guard historyTask == nil else { return }
            if let lastHistoryRefreshElapsedNS, now - lastHistoryRefreshElapsedNS < refreshNS { return }
        }
        historyTask?.cancel()
        historyRequestOrdinal += 1
        let ordinal = historyRequestOrdinal
        let request = HistoryRequest(seriesIDs: selectedSeriesIDs, range: selectedHistoryRange,
            asOfElapsedNS: now, pointLimit: configuration.historyMaxPointsPerSeries)
        lastHistoryRefreshElapsedNS = now
        // Keep an existing chart visible during automatic refresh.
        if force || ordinal == 1 { presentationModel.beginHistoryLoad() }
        historyTask = Task { [weak self] in
            guard let self else { return }
            defer { if ordinal == historyRequestOrdinal { historyTask = nil } }
            do {
                let result = try await queryHistoryWithBudget(request)
                guard !Task.isCancelled, ordinal == historyRequestOrdinal else { return }
                presentationModel.apply(history: result, request: request, definitions: Array(knownDefinitions.values))
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled, ordinal == historyRequestOrdinal else { return }
                let failure = (error as? MonitorFailure) ?? MonitorFailure(code: .uiData, severity: .fatal,
                    component: "AppSessionRuntime", operation: "history", retryCount: configuration.uiRetryMS.count,
                    sourceID: nil, underlyingCode: String(describing: error))
                presentationModel.applyHistoryFailure(failure)
                if failure.severity == .fatal { await enterFatal(failure) }
            }
        }
    }

    private func queryHistoryWithBudget(_ request: HistoryRequest) async throws -> HistoryResult {
        var attempt = 0
        let policy = RetryPolicy(configuration: configuration)
        while true {
            try Task.checkCancellation()
            do { return try await coordinator.queryHistory(request) }
            catch is CancellationError { throw CancellationError() }
            catch {
                let failure = (error as? MonitorFailure) ?? MonitorFailure(code: .databaseRead, severity: .fatal,
                    component: "AppSessionRuntime", operation: "history", retryCount: attempt, sourceID: nil,
                    underlyingCode: String(describing: error))
                if failure.underlyingCode == "superseded" { throw CancellationError() }
                if failure.underlyingCode == "boundary_budget_exceeded" {
                    throw MonitorFailure(code: .uiData, severity: .degraded, component: "AppSessionRuntime",
                        operation: "historyBudget", retryCount: 0, sourceID: nil,
                        underlyingCode: "历史分段边界超过点数上限，请缩短范围；无法在保持缺口和来源边界的同时减点")
                }
                guard policy.isRetryable(failure, domain: .uiHistory), let wait = policy.waitMS(for: .uiHistory, afterFailureIndex: attempt) else {
                    throw MonitorFailure(code: policy.isRetryable(failure, domain: .uiHistory) ? .uiData : failure.code,
                        severity: .fatal, component: failure.component, operation: failure.operation, retryCount: attempt,
                        sourceID: failure.sourceID, underlyingCode: failure.underlyingCode)
                }
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000)
            }
        }
    }

    func updateSelectedSeries(from snapshot: Snapshot, primaryMetricID: MetricID) {
        for value in snapshot.values {
            knownDefinitions[value.definition.seriesID] = value.definition
            lastSeenDefinitionElapsedNS[value.definition.seriesID] = snapshot.asOf.elapsedNS
        }
        let cutoff = snapshot.asOf.elapsedNS - HistoryRange.threeDays.rawValue * 1_000_000_000
        knownDefinitions = knownDefinitions.filter { lastSeenDefinitionElapsedNS[$0.key, default: 0] >= cutoff }
        lastSeenDefinitionElapsedNS = lastSeenDefinitionElapsedNS.filter { knownDefinitions[$0.key] != nil }
        let availableMetrics = Set(snapshot.values.map { $0.definition.metricID })
        selectedMetricIDs.formIntersection(availableMetrics)
        if selectedMetricIDs.isEmpty { selectedMetricIDs = [primaryMetricID] }
        resolveSelectedSeries(asOfElapsedNS: snapshot.asOf.elapsedNS)
    }

    private func resolveSelectedSeries(asOfElapsedNS: Int64) {
        let cutoff = asOfElapsedNS - selectedHistoryRange.rawValue * 1_000_000_000
        selectedSeriesIDs = knownDefinitions.values.filter {
            selectedMetricIDs.contains($0.metricID) && lastSeenDefinitionElapsedNS[$0.seriesID, default: 0] >= cutoff
        }.sorted {
            if $0.metricID != $1.metricID { return $0.metricID.rawValue < $1.metricID.rawValue }
            return $0.definitionVersion < $1.definitionVersion
        }.map(\.seriesID)
    }
}
