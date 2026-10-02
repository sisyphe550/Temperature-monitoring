import Foundation
import SensorRuntime
import TemperatureCore
import TemperaturePresentation

enum AppSessionError: Error, Sendable {
    case missingSensorWorker
    case startupFailed(String)
}

@MainActor
final class AppSessionRuntime {
    private let presentationModel: PresentationModel
    private let clock: MonitorClock
    private let coordinator: SessionCoordinator
    private let configuration: RuntimeConfiguration
    private let profile: SensorProfile
    private let primaryCPUMetricID: MetricID
    private var snapshotTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    private var historyRequestOrdinal: UInt64 = 0
    private var lastHistoryRefreshElapsedNS: Int64?
    private var selectedHistoryRange: HistoryRange = .fiveMinutes
    private var selectedSeriesIDs: [SeriesID] = []

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
    }

    static func makeProduction(
        presentationModel: PresentationModel,
        primaryCPUMetricID: MetricID
    ) throws -> AppSessionRuntime {
        let configuration = try AppBundleConfiguration.loadRuntimeConfiguration()
        let profile = try AppBundleConfiguration.loadProfile()
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

    var canApplyLiveControls: Bool {
        snapshotTask != nil
    }

    func start() {
        guard snapshotTask == nil else {
            return
        }
        snapshotTask = Task { [weak self] in
            await self?.run()
        }
    }

    func stop() async {
        snapshotTask?.cancel()
        snapshotTask = nil
        historyTask?.cancel()
        historyTask = nil
        historyRequestOrdinal += 1
        await coordinator.stop()
    }

    func currentHistoryRange() -> HistoryRange {
        selectedHistoryRange
    }

    func setHistoryRange(_ range: HistoryRange) {
        selectedHistoryRange = range
        requestHistoryReload(force: true)
    }

    func setCPUPeriod(milliseconds: Int) async throws {
        try await coordinator.setCPUPeriod(milliseconds: milliseconds)
    }

    private func run() async {
        do {
            let sessionID = SessionID(UUID())
            let now = clock.now()
            let metadata = SessionMetadata(
                sessionID: sessionID,
                startedWallUnixNS: now.wallUnixNS,
                model: profile.model,
                osBuild: ProcessInfo.processInfo.operatingSystemVersionString,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            )
            try await coordinator.start(sessionMetadata: metadata)
            guard let stream = await coordinator.snapshots() else {
                throw AppSessionError.startupFailed("snapshot stream unavailable")
            }
            for await snapshot in stream {
                if Task.isCancelled {
                    break
                }
                presentationModel.apply(snapshot: snapshot)
                updateSelectedSeries(from: snapshot, primaryMetricID: primaryCPUMetricID)
                requestHistoryReload()
            }
        } catch {
            let receipt = await coordinator.recordFatal(
                MonitorFailure(
                    code: .appInit,
                    severity: .fatal,
                    component: "AppSessionRuntime",
                    operation: "start",
                    retryCount: 0,
                    sourceID: nil,
                    underlyingCode: String(describing: error)
                ),
                reportPath: nil
            )
            presentationModel.enterFatal(receipt)
        }
    }

    private func requestHistoryReload(force: Bool = false) {
        guard !selectedSeriesIDs.isEmpty else { return }
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
            do {
                let result = try await coordinator.queryHistory(request)
                guard !Task.isCancelled, ordinal == historyRequestOrdinal else { return }
                presentationModel.apply(history: result, request: request)
            } catch {
                guard !Task.isCancelled, ordinal == historyRequestOrdinal else { return }
                presentationModel.applyHistoryFailure(MonitorFailure(code: .databaseRead, severity: .degraded,
                    component: "AppSessionRuntime", operation: "history", retryCount: 0, sourceID: nil,
                    underlyingCode: String(describing: error)))
            }
            if ordinal == historyRequestOrdinal { historyTask = nil }
        }
    }

    func updateSelectedSeries(from snapshot: Snapshot, primaryMetricID: MetricID) {
        if let primary = snapshot.values.first(where: { $0.definition.metricID == primaryMetricID }) {
            selectedSeriesIDs = [primary.definition.seriesID]
        }
    }
}
