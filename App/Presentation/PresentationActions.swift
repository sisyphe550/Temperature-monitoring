import Foundation
import TemperatureCore

@MainActor
protocol PresentationActions: AnyObject {
    func openDashboard()
    func openSettings()
    func setCPUPeriod(milliseconds: Int)
    func currentHistoryRange() -> HistoryRange
    func setHistoryRange(_ range: HistoryRange)
    func quit()
}
