import AppKit
import Foundation
import TemperatureCore
import TemperaturePresentation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, PresentationActions {
    private let presentationModel: PresentationModel
    private let primaryCPUMetricID: MetricID
    private var statusItemController: StatusItemController?
    private var dashboardController: DashboardWindowController?
    private var settingsController: SettingsWindowController?
    private var sessionRuntime: AppSessionRuntime?
    private var fixtureName: String?
    private var fixtureGeneration: UInt64 = 1
    private var selectedHistoryRange: HistoryRange = .fiveMinutes
    private var selectedHistoryMetricIDs: Set<MetricID> = []
    private var fatalExitTask: Task<Void, Never>?
    private var sleepWakeTask: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var terminationTask: Task<Void, Never>?
    private var terminationDeadlineTask: Task<Void, Never>?
    private var terminationReplySent = false

    override init() {
        primaryCPUMetricID = try! MetricID(validating: "cpu.zone.max")
        presentationModel = PresentationModel(primaryCPUMetricID: primaryCPUMetricID)
        selectedHistoryMetricIDs = [primaryCPUMetricID]
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if UIFixtureLaunchPolicy.rejectsReleaseFixtureLaunch(
            isDebugBuild: Self.isDebugBuild,
            hasFixtureArgument: Self.fixtureName(from: CommandLine.arguments) != nil
        ) {
            NSApp.terminate(nil)
            return
        }
        fixtureName = Self.fixtureName(from: CommandLine.arguments)
        if let fixtureName, UIFixtureLaunchPolicy.accepts(
            fixtureName: fixtureName,
            isDebugBuild: Self.isDebugBuild
        ) {
            UIFixtures.apply(named: fixtureName, to: presentationModel)
        } else {
            do {
                let runtime = try AppSessionRuntime.makeProduction(presentationModel: presentationModel,
                    primaryCPUMetricID: primaryCPUMetricID)
                runtime.setFatalHandler { [weak self, weak runtime] receipt in self?.showFatal(receipt, delayMS: runtime?.remainingFatalMS(receipt)) }
                sessionRuntime = runtime
                runtime.start()
            } catch {
                let now = SystemClock().now()
                let failure = (error as? MonitorFailure) ?? MonitorFailure(code: .appInit, severity: .fatal,
                    component: "AppDelegate", operation: "makeProduction", retryCount: 0, sourceID: nil,
                    underlyingCode: String(describing: error))
                // This fallback also works when the configuration resources themselves cannot load.
                let fallbackConfiguration = (try? AppBundleConfiguration.loadRuntimeConfiguration()) ?? (try? Configuration.bundledDefaults())
                var reportPath: String?
                if let configuration = fallbackConfiguration,
                   let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                    let directory = support.appendingPathComponent(configuration.bundleID).appendingPathComponent("Diagnostics")
                    let logger = DiagnosticLogger(directory: directory, configuration: configuration)
                    let context = DiagnosticContext(sessionID: SessionID(UUID()), appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                        model: "startup", osBuild: ProcessInfo.processInfo.operatingSystemVersionString)
                    try? logger.append(DiagnosticLogEntry(failure: failure, context: context))
                    let report = FatalReport(frozenFailure: failure, sessionID: context.sessionID, appVersion: context.appVersion,
                        model: context.model, osBuild: context.osBuild, incompleteShutdownSteps: [], writtenAt: Date())
                    reportPath = (try? ReportWriter(directory: directory, configuration: configuration).write(report))?.url?.path
                }
                fputs("TemperatureMonitor startup failure: \(failure.code.rawValue) \(failure.underlyingCode ?? failure.operation)\n", stderr)
                let intervalNS = Int64(fallbackConfiguration?.fatalDisplayMS ?? 30_000) * 1_000_000
                let deadline = Timestamp(elapsedNS: now.elapsedNS + intervalNS, wallUnixNS: now.wallUnixNS + intervalNS)
                let receipt = FatalDisplayReceipt(failure: failure, visibleAt: now, exitDeadline: deadline, reportPath: reportPath)
                presentationModel.enterFatal(receipt)
                showFatal(receipt)
            }
        }
        statusItemController = StatusItemController(
            presentationModel: presentationModel,
            actions: self
        )
        statusItemController?.install()
        installWorkspaceNotifications()
        applyUILaunchOptions(from: CommandLine.arguments)
        if fixtureName == nil { openDashboard() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openDashboard()
        return true
    }

    private func showFatal(_ receipt: FatalDisplayReceipt, delayMS: Int? = nil) {
        openDashboard()
        guard fatalExitTask == nil else { return }
        let delayNS = delayMS.map { Int64($0) * 1_000_000 } ?? max(0, receipt.exitDeadline.elapsedNS - receipt.visibleAt.elapsedNS)
        fatalExitTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delayNS)) } catch { return }
            self?.quit()
        }
    }

    private func applyUILaunchOptions(from arguments: [String]) {
        guard Self.isDebugBuild else {
            return
        }
        guard let index = arguments.firstIndex(of: "--ui-open"),
              arguments.indices.contains(index + 1) else {
            return
        }
        switch arguments[index + 1] {
        case "dashboard":
            openDashboard()
        case "settings":
            openSettings()
        case "popover":
            statusItemController?.showPopoverForTesting()
        default:
            break
        }
    }

    private func installWorkspaceNotifications() {
        guard sessionRuntime != nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.enqueueWorkspaceTransition(isWake: false) }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.enqueueWorkspaceTransition(isWake: true) }
            },
        ]
    }

    private func enqueueWorkspaceTransition(isWake: Bool) {
        let previous = sleepWakeTask
        sleepWakeTask = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled, let runtime = self?.sessionRuntime else { return }
            if isWake { await runtime.resumeAfterWake() }
            else { await runtime.suspendForSleep() }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let runtime = sessionRuntime else { return .terminateNow }
        guard terminationTask == nil else { return .terminateLater }
        fatalExitTask?.cancel()
        sleepWakeTask?.cancel()
        terminationTask = Task { [weak self] in
            await runtime.stop()
            self?.finishTermination()
        }
        terminationDeadlineTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(runtime.shutdownBudgetMS) * 1_000_000) } catch { return }
            await runtime.recordShutdownDeadlineExceeded()
            self?.finishTermination()
        }
        return .terminateLater
    }

    private func finishTermination() {
        guard !terminationReplySent else { return }
        terminationReplySent = true
        terminationDeadlineTask?.cancel()
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll()
        statusItemController?.uninstall()
    }

    func openDashboard() {
        if dashboardController == nil {
            dashboardController = DashboardWindowController(
                presentationModel: presentationModel,
                actions: self
            )
        }
        dashboardController?.showWindow()
    }

    func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(
                presentationModel: presentationModel,
                actions: self
            )
        }
        settingsController?.showWindow()
    }

    func currentHistoryMetricIDs() -> Set<MetricID> { sessionRuntime?.currentHistoryMetricIDs() ?? selectedHistoryMetricIDs }

    func setHistoryMetricIDs(_ metricIDs: Set<MetricID>) {
        if let sessionRuntime { sessionRuntime.setHistoryMetricIDs(metricIDs); return }
        guard fixtureName != nil, !metricIDs.isEmpty, metricIDs.count <= 8 else { return }
        selectedHistoryMetricIDs = metricIDs
        UIFixtures.applyHistory(to: presentationModel, range: selectedHistoryRange, metricIDs: selectedHistoryMetricIDs)
    }

    func currentHistoryRange() -> HistoryRange {
        sessionRuntime?.currentHistoryRange() ?? selectedHistoryRange
    }

    func setHistoryRange(_ range: HistoryRange) {
        if let sessionRuntime {
            sessionRuntime.setHistoryRange(range)
            return
        }
        guard fixtureName != nil else {
            return
        }
        selectedHistoryRange = range
        UIFixtures.applyHistory(to: presentationModel, range: range, metricIDs: selectedHistoryMetricIDs)
    }

    func setCPUPeriod(milliseconds: Int) {
        guard TemperatureFormatting.cpuPeriodOptionsMS.contains(milliseconds) else {
            return
        }
        if let sessionRuntime {
            Task {
                try? await sessionRuntime.setCPUPeriod(milliseconds: milliseconds)
            }
            return
        }
        guard fixtureName != nil else {
            return
        }
        guard case .running = presentationModel.state else {
            return
        }
        fixtureGeneration += 1
        if fixtureName == "sources" {
            UIFixtures.applySources(to: presentationModel, cpuPeriodMS: milliseconds, generation: fixtureGeneration)
        } else {
            UIFixtures.applyBasic(to: presentationModel, cpuPeriodMS: milliseconds, generation: fixtureGeneration)
        }
        UIFixtures.applyHistory(to: presentationModel, range: selectedHistoryRange, metricIDs: selectedHistoryMetricIDs)
    }

    func quit() {
        // AppKit enters a nested loop for terminateLater. Run outside a Swift
        // MainActor job (or main dispatch block) so async shutdown can reply.
        RunLoop.main.perform(inModes: [.common]) {
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private static func fixtureName(from arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "--ui-fixture"),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}
