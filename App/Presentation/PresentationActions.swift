import Foundation
import TemperatureCore
import TemperaturePresentation

@MainActor
protocol PresentationActions: AnyObject {
    func openDashboard()
    func openSettings()
    func setCPUPeriod(milliseconds: Int)
    func currentHistoryMetricIDs() -> Set<MetricID>
    func setHistoryMetricIDs(_ metricIDs: Set<MetricID>)
    func currentHistoryRange() -> HistoryRange
    func setHistoryRange(_ range: HistoryRange)
    func applyCPUWarningRule(_ rule: CPUWarningRule) async throws
    func cpuWarningNotificationStatus() -> CPUWarningNotificationStatus?
    func cpuWarningPreferencesIssueText() -> String?
    func quit()
}
