import SwiftUI

@main
struct TemperatureMonitorApp: App {
    var body: some Scene {
        WindowGroup {
            Text("TemperatureMonitor")
                .frame(minWidth: 800, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
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
