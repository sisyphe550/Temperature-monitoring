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
    private let coordinator: SessionCoordinator
    private let configuration: RuntimeConfiguration
    private let profile: SensorProfile
    private let primaryCPUMetricID: MetricID
    private var snapshotTask: Task<Void, Never>?
    private var selectedHistoryRange: HistoryRange = .fiveMinutes
    private var selectedSeriesIDs: [SeriesID] = []

    init(
        presentationModel: PresentationModel,
        coordinator: SessionCoordinator,
        configuration: RuntimeConfiguration,
        profile: SensorProfile,
        primaryCPUMetricID: MetricID
    ) {
        self.presentationModel = presentationModel
        self.coordinator = coordinator
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
        let transport = WorkerClient(
            configuration: WorkerClientConfiguration(executableURL: workerURL)
        )
        let client = QualifiedSensorClient(
            transport: transport,
            registry: ProfileRegistry(profile: profile)
        )
        let coordinator = SessionCoordinator(
            clock: SystemClock(),
            client: client,
            configuration: configuration,
            applicationSupportBase: supportBase
        )
        return AppSessionRuntime(
            presentationModel: presentationModel,
            coordinator: coordinator,
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
        await coordinator.stop()
    }

    func currentHistoryRange() -> HistoryRange {
        selectedHistoryRange
    }

    func setHistoryRange(_ range: HistoryRange) {
        selectedHistoryRange = range
        Task { await reloadHistory() }
    }

    func setCPUPeriod(milliseconds: Int) async throws {
        try await coordinator.setCPUPeriod(milliseconds: milliseconds)
    }

    private func run() async {
        do {
            let sessionID = SessionID(UUID())
            let now = SystemClock().now()
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
            await reloadHistory()
            for await snapshot in stream {
                if Task.isCancelled {
                    break
                }
                presentationModel.apply(snapshot: snapshot)
                updateSelectedSeries(from: snapshot, primaryMetricID: primaryCPUMetricID)
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

    private func reloadHistory() async {
        guard !selectedSeriesIDs.isEmpty else {
            return
        }
        presentationModel.beginHistoryLoad()
        let request = HistoryRequest(
            seriesIDs: selectedSeriesIDs,
            range: selectedHistoryRange,
            asOfElapsedNS: SystemClock().now().elapsedNS,
            pointLimit: configuration.historyMaxPointsPerSeries
        )
        do {
            let result = try await coordinator.queryHistory(request)
            presentationModel.apply(history: result, request: request)
        } catch {
            presentationModel.applyHistoryFailure(
                MonitorFailure(
                    code: .databaseRead,
                    severity: .degraded,
                    component: "AppSessionRuntime",
                    operation: "history",
                    retryCount: 0,
                    sourceID: nil,
                    underlyingCode: String(describing: error)
                )
            )
        }
    }

    func updateSelectedSeries(from snapshot: Snapshot, primaryMetricID: MetricID) {
        if let primary = snapshot.values.first(where: { $0.definition.metricID == primaryMetricID }) {
            selectedSeriesIDs = [primary.definition.seriesID]
        }
    }
}
