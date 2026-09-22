import AppKit
import Foundation
import TemperatureCore
import TemperaturePresentation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let presentationModel: PresentationModel
    private var statusItemController: StatusItemController?
    private var fixtureName: String?

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
            applyFixture(named: fixtureName)
        }
        statusItemController = StatusItemController(presentationModel: presentationModel)
        statusItemController?.install()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusItemController?.uninstall()
    }

    private func applyFixture(named name: String) {
        switch name {
        case "basic":
            let now = Timestamp(elapsedNS: 200_000_000, wallUnixNS: 1_700_000_000_200_000_000)
            let seriesID = (try? SeriesID(validating: "00000000-0000-4000-8000-000000000101"))!
            let definition = SeriesDefinition(
                seriesID: seriesID,
                metricID: (try? MetricID(validating: "cpu.zone.max"))!,
                definitionVersion: 1,
                kind: .cpuZone,
                displayName: "CPU Max",
                memberSourceIDs: [(try? SourceID(validating: "00000000-0000-4000-8000-000000000001"))!],
                formula: .maximum
            )
            _ = presentationModel.apply(
                snapshot: Snapshot(
                    asOf: now,
                    values: [
                        LatestValue(
                            definition: definition,
                            state: .available(
                                ema: EMAValue(
                                    sampleID: "fixture:1",
                                    seriesID: seriesID,
                                    segment: 1,
                                    timestamp: now,
                                    valueC: 58.3
                                ),
                                lastSuccessfulAt: now,
                                lastFailure: nil
                            )
                        )
                    ],
                    gapIDs: [],
                    cpuPeriodMS: 200,
                    generation: 1
                )
            )
        default:
            break
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
