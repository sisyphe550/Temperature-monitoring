import XCTest

final class TemperatureMonitorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBasicFixtureShowsLiveTemperature() throws {
        let app = launch(fixture: "basic")
        let statusButton = app.menuBars.statusItems["status.temperature"]
        XCTAssertTrue(statusButton.waitForExistence(timeout: 10))
        XCTAssertEqual(statusValue(from: statusButton), "58.3 °C")
    }

    func testStaleFixtureShowsPlaceholderInStatusItem() throws {
        let app = launch(fixture: "stale")
        let statusButton = app.menuBars.statusItems["status.temperature"]
        XCTAssertTrue(statusButton.waitForExistence(timeout: 10))
        XCTAssertEqual(statusValue(from: statusButton), "— °C")
    }

    func testFatalFixtureShowsFatalCodeInDashboard() throws {
        let app = launch(fixture: "fatal", open: "dashboard")
        let fatalCode = app.staticTexts["fatal.code"]
        XCTAssertTrue(fatalCode.waitForExistence(timeout: 10))
        XCTAssertEqual(fatalCode.value as? String ?? fatalCode.title, "SENSOR-READ-002")
        XCTAssertTrue(app.staticTexts["fatal.countdown"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["fatal.quit"].exists)
        XCTAssertTrue(app.buttons["fatal.copy"].exists)
    }

    func testSettingsWindowOpens() throws {
        let app = launch(fixture: "basic", open: "settings")
        let settingsWindow = app.windows["设置"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        XCTAssertTrue(app.popUpButtons["cpu.period"].exists)
    }

    func testHistoryChartLoadsInDashboard() throws {
        let app = launch(fixture: "basic", open: "dashboard")
        let dashboardWindow = app.windows["温度监测"]
        XCTAssertTrue(dashboardWindow.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["history.range"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["history.chart"].firstMatch.waitForExistence(timeout: 5))
    }

    func testCPUPeriodPicker() throws {
        let app = launch(fixture: "basic", open: "dashboard")
        let dashboardWindow = app.windows["温度监测"]
        XCTAssertTrue(dashboardWindow.waitForExistence(timeout: 10))
        let picker = app.popUpButtons["cpu.period"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.click()
        app.menuItems["500 ms"].click()
        XCTAssertEqual(picker.value as? String, "500 ms")
    }

    func testDashboardCloseKeepsStatusItem() throws {
        let app = launch(fixture: "basic", open: "dashboard")
        let statusButton = app.menuBars.statusItems["status.temperature"]
        XCTAssertTrue(statusButton.waitForExistence(timeout: 10))
        let dashboardWindow = app.windows["温度监测"]
        XCTAssertTrue(dashboardWindow.waitForExistence(timeout: 5))
        dashboardWindow.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertFalse(dashboardWindow.waitForExistence(timeout: 2))
        XCTAssertTrue(statusButton.exists)
        XCTAssertEqual(statusValue(from: statusButton), "58.3 °C")
    }

    func testSourcesFixtureListsRows() throws {
        let app = launch(fixture: "sources", open: "dashboard")
        let dashboardWindow = app.windows["温度监测"]
        XCTAssertTrue(dashboardWindow.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Tp01"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["SSD"].exists)
        XCTAssertTrue(app.staticTexts["Battery"].exists)
    }

    func testReleaseBuildRejectsFixtureLaunch() throws {
        throw XCTSkip("Release fixture rejection is validated in UIFixtureLaunchPolicy unit coverage.")
    }

    private func launch(fixture: String, open: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["--ui-fixture", fixture]
        if let open {
            arguments.append(contentsOf: ["--ui-open", open])
        }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func statusValue(from statusButton: XCUIElement) -> String {
        (statusButton.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? statusButton.title
    }
}
