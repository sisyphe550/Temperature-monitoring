import Foundation

@MainActor
protocol PresentationActions: AnyObject {
    func openDashboard()
    func openSettings()
    func setCPUPeriod(milliseconds: Int)
    func quit()
}
