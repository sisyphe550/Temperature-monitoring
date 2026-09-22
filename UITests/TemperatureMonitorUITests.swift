import XCTest

final class TemperatureMonitorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBasicFixtureShowsLiveTemperature() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "basic"]
        app.launch()

        let statusButton = app.menuBars.statusItems["status.temperature"]
        XCTAssertTrue(statusButton.waitForExistence(timeout: 10))
        let displayed = (statusButton.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? statusButton.title
        XCTAssertEqual(displayed, "58.3 °C")
    }

    func testReleaseBuildRejectsFixtureLaunch() throws {
        throw XCTSkip("Release fixture rejection is validated in UIFixtureLaunchPolicy unit coverage.")
    }
}
