import XCTest

final class TemperatureMonitorUITests: XCTestCase {
    func testPlaceholderRequiresXcodeProject() throws {
        throw XCTSkip("TemperatureMonitor.xcodeproj and full Xcode are required for UI tests (T07.1 external dependency).")
    }
}
