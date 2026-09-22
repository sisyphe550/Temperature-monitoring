import AppKit
import Foundation
import TemperatureCore
import TemperaturePresentation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, PresentationActions {
    private let presentationModel: PresentationModel
    private var statusItemController: StatusItemController?
    private var dashboardController: DashboardWindowController?
    private var settingsController: SettingsWindowController?
    private var fixtureName: String?
    private var fixtureGeneration: UInt64 = 1

    override init() {
        presentationModel = PresentationModel(
            primaryCPUMetricID: try! MetricID(validating: "cpu.zone.max")
        )
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

    func setCPUPeriod(milliseconds: Int) {
        guard TemperatureFormatting.cpuPeriodOptionsMS.contains(milliseconds) else {
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
