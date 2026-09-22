import SwiftUI

@main
struct TemperatureMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

enum UIFixtureLaunchPolicy {
    static func accepts(fixtureName: String, isDebugBuild: Bool) -> Bool {
        isDebugBuild && !fixtureName.isEmpty
    }

    static func rejectsReleaseFixtureLaunch(isDebugBuild: Bool, hasFixtureArgument: Bool) -> Bool {
        !isDebugBuild && hasFixtureArgument
    }
}
