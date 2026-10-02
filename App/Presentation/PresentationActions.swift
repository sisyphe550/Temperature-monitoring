import Foundation
import TemperatureCore

@MainActor
protocol PresentationActions: AnyObject {
    func openDashboard()
    func openSettings()
    func setCPUPeriod(milliseconds: Int)
    func currentHistoryMetricIDs() -> Set<MetricID>
    func setHistoryMetricIDs(_ metricIDs: Set<MetricID>)
    func currentHistoryRange() -> HistoryRange
    func setHistoryRange(_ range: HistoryRange)
    func quit()
}
