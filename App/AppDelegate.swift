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

    override init() {
        primaryCPUMetricID = try! MetricID(validating: "cpu.zone.max")
        presentationModel = PresentationModel(primaryCPUMetricID: primaryCPUMetricID)
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
        } else if Bundle.main.sensorWorkerExecutableURL != nil {
            sessionRuntime = try? AppSessionRuntime.makeProduction(
                presentationModel: presentationModel,
                primaryCPUMetricID: primaryCPUMetricID
            )
            sessionRuntime?.start()
        }
        statusItemController = StatusItemController(
            presentationModel: presentationModel,
            actions: self
        )
        statusItemController?.install()
        applyUILaunchOptions(from: CommandLine.arguments)
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

    func applicationWillTerminate(_ notification: Notification) {
        statusItemController?.uninstall()
        Task {
            await sessionRuntime?.stop()
        }
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
        UIFixtures.applyHistory(to: presentationModel, range: range)
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
        UIFixtures.applyBasic(
            to: presentationModel,
            cpuPeriodMS: milliseconds,
            generation: fixtureGeneration
        )
        UIFixtures.applyHistory(to: presentationModel, range: selectedHistoryRange)
    }

    func quit() {
        NSApp.terminate(nil)
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
