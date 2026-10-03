import AppKit
import Darwin
import Foundation
import XCTest

@MainActor
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
        for (metricID, title) in [("cpu.member.tp01", "Tp01"), ("ssd.temp", "SSD"), ("battery.temp", "Battery")] {
            let source = app.checkBoxes["history.select.\(metricID)"]
            XCTAssertTrue(source.waitForExistence(timeout: 5))
            XCTAssertTrue(source.label.contains(title))
            XCTAssertTrue(source.label.contains("°C"))
        }
    }

    func testReleaseBuildRejectsFixtureLaunch() throws {
        throw XCTSkip("Release fixture rejection is validated in UIFixtureLaunchPolicy unit coverage.")
    }

    func testStaleFixtureShowsExplicitExpiredReason() throws {
        let app = launch(fixture: "stale", open: "dashboard")
        let primary = app.checkBoxes["history.select.cpu.zone.max"]
        XCTAssertTrue(primary.waitForExistence(timeout: 10))
        XCTAssertTrue(primary.label.contains("数据已过期"))
    }

    func testDashboardOffersSourceSelectionAndTemperatureComparison() throws {
        let app = launch(fixture: "sources", open: "dashboard")
        XCTAssertTrue(app.checkBoxes["history.select.cpu.zone.max"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.checkBoxes["history.select.ssd.temp"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["temperature.comparison"].firstMatch.exists)
        let ssd = app.checkBoxes["history.select.ssd.temp"]
        ssd.click()
        let checked = (ssd.value as? NSNumber)?.intValue ?? Int(ssd.value as? String ?? "")
        XCTAssertEqual(checked, 1)
        let sources = app.staticTexts["history.sources"]
        XCTAssertTrue(sources.waitForExistence(timeout: 5))
        XCTAssertTrue((sources.value as? String ?? sources.label).contains("SSD"))
        app.buttons["history.range.1 小时"].click()
        XCTAssertTrue((sources.value as? String ?? sources.label).contains("SSD"))
    }

    func testCPUPeriodPickerSupportsAllFiveOptions() throws {
        let app = launch(fixture: "sources", open: "dashboard")
        let picker = app.popUpButtons["cpu.period"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        for label in ["50 ms", "100 ms", "200 ms", "500 ms", "1000 ms"] {
            picker.click()
            app.menuItems[label].click()
            XCTAssertEqual(picker.value as? String, label)
        }
        XCTAssertTrue(app.checkBoxes["history.select.ssd.temp"].exists)
    }

    func testCachedFixtureLabelsStatusAndReadFailure() throws {
        let app = launch(fixture: "cached", open: "dashboard")
        let status = app.menuBars.statusItems["status.temperature"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(statusValue(from: status).contains("缓存"))
        let primary = app.checkBoxes["history.select.cpu.zone.max"]
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        XCTAssertTrue(primary.label.contains("缓存"))
        XCTAssertTrue(primary.label.contains("timeout"))
    }

    func testUnavailableSourceShowsReasonAndCannotBeSelected() throws {
        let app = launch(fixture: "unavailable", open: "dashboard")
        let ssd = app.checkBoxes["history.select.ssd.temp"]
        XCTAssertTrue(ssd.waitForExistence(timeout: 10))
        XCTAssertFalse(ssd.isEnabled)
        XCTAssertTrue(ssd.label.contains("当前设备未发现"))
    }

    func testSettingsHasDiagnosticsAndLicenseEntries() throws {
        let app = launch(fixture: "sources", open: "settings")
        XCTAssertTrue(app.buttons["settings.logs"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["settings.reports"].exists)
        XCTAssertTrue(app.buttons["settings.licenses"].exists)
    }

    func testDashboardStandardReopenKeepsSelectionAndSamplingPeriod() throws {
        let app = launch(fixture: "sources", open: "dashboard")
        let dashboard = app.windows["温度监测"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10))
        let running = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.sisyphe550.TemperatureMonitor").first { !$0.isTerminated })
        let appURL = try XCTUnwrap(running.bundleURL)
        let processID = running.processIdentifier
        let status = app.menuBars.statusItems["status.temperature"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let initialStatus = statusValue(from: status)
        let member = app.checkBoxes["history.select.cpu.member.tp01"]
        member.click()
        XCTAssertEqual((member.value as? NSNumber)?.intValue ?? Int(member.value as? String ?? ""), 1)
        let picker = app.popUpButtons["cpu.period"]
        picker.click()
        app.menuItems["500 ms"].click()
        XCTAssertEqual(picker.value as? String, "500 ms")
        app.buttons["history.range.1 小时"].click()
        XCTAssertTrue(realText(app.staticTexts["history.sources"]).contains("Tp01"))
        realScreenshot(dashboard, name: "Fixture-before-standard-reopen")

        dashboard.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(dashboard.waitForNonExistence(timeout: 5))
        XCTAssertTrue(status.exists)
        XCTAssertEqual(statusValue(from: status), initialStatus)
        XCTAssertTrue(NSWorkspace.shared.open(appURL), "LaunchServices could not send the standard reopen event.")
        XCTAssertTrue(dashboard.waitForExistence(timeout: 5))
        XCTAssertFalse(running.isTerminated)
        XCTAssertEqual(NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.sisyphe550.TemperatureMonitor").filter { !$0.isTerminated }.map(\.processIdentifier), [processID])
        XCTAssertEqual(picker.value as? String, "500 ms")
        XCTAssertEqual((member.value as? NSNumber)?.intValue ?? Int(member.value as? String ?? ""), 1)
        XCTAssertTrue(realText(app.staticTexts["history.sources"]).contains("Tp01"))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "历史平均温度")).firstMatch.exists)
        realScreenshot(dashboard, name: "Fixture-standard-reopen-same-process")
    }

    func testDashboardQuitButtonTerminatesApp() throws {
        let app = launch(fixture: "sources", open: "dashboard")
        XCTAssertTrue(app.windows["温度监测"].waitForExistence(timeout: 10))
        let quit = app.buttons["app.quit"]
        XCTAssertTrue(quit.waitForExistence(timeout: 5))
        realScreenshot(app.windows["温度监测"], name: "Fixture-window-quit-button")
        quit.click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
    }

    // Opt-in Mac16,13 Release smoke acceptance: five 8-second phases, not endurance qualification.
    func testLocalReleaseAppRealHardwareUI() throws {
        let environment = ProcessInfo.processInfo.environment
        let paths = [environment["TM_REAL_APP_PATH"], environment["TEST_RUNNER_TM_REAL_APP_PATH"]]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let path = paths.first(where: { !$0.isEmpty }) else {
            throw XCTSkip("Set TM_REAL_APP_PATH or TEST_RUNNER_TM_REAL_APP_PATH to an already built Release app on the target Mac.")
        }
        let appURL = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        let bundle = try XCTUnwrap(Bundle(url: appURL), "Release app bundle does not exist: \(path)")
        let bundleID = try XCTUnwrap(bundle.bundleIdentifier)
        XCTAssertEqual(bundleID, "io.github.sisyphe550.TemperatureMonitor")
        // The test runner is sandboxed; read the unsandboxed Release app's user directory.
        let account = try XCTUnwrap(getpwuid(getuid()))
        let userHome = URL(fileURLWithPath: String(cString: account.pointee.pw_dir), isDirectory: true)
        let sessionsRoot = userHome.appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Sessions", isDirectory: true)
        let app = XCUIApplication(url: appURL)
        XCTAssertEqual(app.state, .notRunning, "Normally quit an existing TemperatureMonitor session before this acceptance run.")
        let previousSessions = try realSessionNames(in: sessionsRoot)
        app.launchArguments = []
        addTeardownBlock {
            await MainActor.run {
                guard app.state != .notRunning else { return }
                if !app.windows["温度监测"].exists {
                    XCTAssertTrue(NSWorkspace.shared.open(appURL), "LaunchServices could not reopen the real app for normal cleanup.")
                }
                let quit = app.buttons["app.quit"]
                if quit.waitForExistence(timeout: 3) { quit.click() }
                XCTAssertTrue(app.wait(for: .notRunning, timeout: 10), "The real app did not finish normal window-button shutdown.")
            }
        }
        app.launch()
        let status = app.menuBars.statusItems["status.temperature"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(realWaitUntil(timeout: 20) { self.realHasTemperature(self.statusValue(from: status)) })
        let statusAccessibility = "Status AX: exists \(status.exists); isHittable \(status.isHittable); frame \(status.frame). Right-click/context menu has not been accepted by this test."
        let statusEvidence = XCTAttachment(string: statusAccessibility)
        statusEvidence.name = "Release-status-item-accessibility-and-scope"
        statusEvidence.lifetime = .keepAlways
        add(statusEvidence)
        let dashboard = app.windows["温度监测"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10), "Production launch must show the dashboard without fixture or --ui-open arguments.")
        XCTAssertTrue(app.buttons["app.quit"].exists)
        realScreenshot(dashboard, name: "Release-production-startup-dashboard")

        let cpuSources = app.checkBoxes.matching(NSPredicate(format: "identifier MATCHES %@", "history.select.cpu.zone.[0-9]+"))
        XCTAssertEqual(cpuSources.count, 12)
        let cpuLabels = cpuSources.allElementsBoundByIndex.map(\.label)
        let expectedKeys: Set<String> = ["Te05", "Te0S", "Te09", "Te0H", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"]
        XCTAssertEqual(Set(cpuLabels.compactMap { $0.split(separator: ",").first.map(String.init) }), expectedKeys)
        XCTAssertTrue(cpuLabels.allSatisfy { $0.contains("°C") })
        for metric in ["storage.ssd", "power.battery"] {
            let source = app.checkBoxes["history.select.\(metric)"]
            XCTAssertTrue(source.waitForExistence(timeout: 5))
            XCTAssertTrue(realWaitUntil(timeout: 5) {
                ["应用读取", "缓存 · 暂未更新 · ", "数据已过期", "不可用 · "].contains { source.label.contains($0) }
            }, source.label)
            if source.label.contains("不可用 · ") {
                XCTAssertFalse(source.isEnabled)
                XCTAssertFalse(source.label.components(separatedBy: "不可用 · ").last?.isEmpty ?? true)
            }
        }
        let optionalLabels = ["storage.ssd", "power.battery"].map { app.checkBoxes["history.select.\($0)"].label }
        XCTAssertTrue(realWaitUntil(timeout: 5) { ((try? self.realSessionNames(in: sessionsRoot)) ?? []).subtracting(previousSessions).count == 1 })
        let createdSessions = try realSessionNames(in: sessionsRoot).subtracting(previousSessions)
        let sessionName = try XCTUnwrap(createdSessions.first)
        let sessionDirectory = sessionsRoot.appendingPathComponent(sessionName, isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionDirectory.appendingPathComponent("monitor.sqlite").path))

        // Select one real CPU member alongside max; optional hardware may be unavailable.
        let member = app.checkBoxes["history.select.cpu.zone.1"]
        member.click()
        XCTAssertEqual((member.value as? NSNumber)?.intValue ?? Int(member.value as? String ?? ""), 1)
        let memberName = try XCTUnwrap(member.label.split(separator: ",").first.map(String.init))
        let historySources = app.staticTexts["history.sources"]
        XCTAssertTrue(realWaitUntil(timeout: 10) {
            historySources.exists && self.realText(historySources).contains("CPU热区最高温度") && self.realText(historySources).contains(memberName)
        })
        XCTAssertTrue(app.descendants(matching: .any)["temperature.comparison"].firstMatch.exists)
        app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -1200)
        realScreenshot(dashboard, name: "Release-optional-source-states")
        app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: 1200)

        let picker = app.popUpButtons["cpu.period"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        var phases: [String] = []
        for milliseconds in [50, 100, 200, 500, 1000] {
            let label = "\(milliseconds) ms"
            picker.click()
            app.menuItems[label].click()
            XCTAssertTrue(realWaitUntil(timeout: 5) { picker.value as? String == label })
            let started = ProcessInfo.processInfo.systemUptime
            Thread.sleep(forTimeInterval: 8)
            let heldSeconds = ProcessInfo.processInfo.systemUptime - started
            XCTAssertTrue(realHasTemperature(statusValue(from: status)), statusValue(from: status))
            XCTAssertFalse(app.staticTexts["fatal.code"].exists)
            XCTAssertEqual(picker.value as? String, label)
            phases.append("\(label): held \(heldSeconds) seconds; status \(statusValue(from: status))")
            realScreenshot(dashboard, name: "Release-CPU-\(milliseconds)ms-after-8s")
        }
        for (label, header) in [("5 分钟", "平滑温度"), ("1 小时", "历史平均温度")] {
            app.buttons["history.range.\(label)"].click()
            let readyHeader = app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", header)).firstMatch
            XCTAssertTrue(realWaitUntil(timeout: 10) {
                readyHeader.exists && historySources.exists && self.realText(historySources).contains(memberName)
            })
            XCTAssertFalse(app.staticTexts["history.failure"].exists)
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "value == %@", "本会话暂无数据")).firstMatch.exists)
            realScreenshot(dashboard, name: "Release-history-\(label)")
        }

        let chart = app.descendants(matching: .any)["history.chart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.45)).click()
        let selection = app.descendants(matching: .any)["history.selection"].firstMatch
        XCTAssertTrue(selection.waitForExistence(timeout: 5), "Equatable history must preserve local point selection.")
        let selectedDetail = ([realText(selection)] + selection.staticTexts.allElementsBoundByIndex.map { realText($0) }).joined(separator: "\n")
        XCTAssertTrue(selectedDetail.contains("°C"), selectedDetail)
        XCTAssertTrue(selectedDetail.contains("个样本"), selectedDetail)
        realScreenshot(dashboard, name: "Release-history-point-selection")

        dashboard.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(dashboard.waitForNonExistence(timeout: 5))
        XCTAssertTrue(status.exists)
        XCTAssertTrue(realHasTemperature(statusValue(from: status)))
        realScreenshot(status, name: "Release-status-after-dashboard-close")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionDirectory.path))
        XCTAssertTrue(NSWorkspace.shared.open(appURL), "LaunchServices could not send the standard reopen event.")
        XCTAssertTrue(dashboard.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, "1000 ms")
        XCTAssertEqual((member.value as? NSNumber)?.intValue ?? Int(member.value as? String ?? ""), 1)
        XCTAssertEqual(try realSessionNames(in: sessionsRoot).subtracting(previousSessions), createdSessions, "Closing and reopening the dashboard must keep the same session.")
        realScreenshot(dashboard, name: "Release-reopened-same-session")

        let quit = app.buttons["app.quit"]
        XCTAssertTrue(quit.waitForExistence(timeout: 3))
        quit.click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sessionDirectory.path), "The session created by this test was not cleaned up.")
        XCTAssertTrue(try realSessionNames(in: sessionsRoot).subtracting(previousSessions).isEmpty)
        let evidence = XCTAttachment(string: "Release app: \(appURL.path)\nSession: \(sessionName)\nCPU12: \(cpuLabels.joined(separator: "\n"))\nOptional: \(optionalLabels.joined(separator: "\n"))\n\(phases.joined(separator: "\n"))\n\(statusAccessibility)\nNormal quit via app.quit: notRunning; new session directory removed.\nScope: production launch, standard LaunchServices reopen, window-button quit, five 8-second phases; not right-click/menu or 5x10-minute or 72-hour qualification.")
        evidence.name = "Release-real-hardware-short-acceptance"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    // Local opt-in acceptance; each period gets 600 awake seconds. System sleep is a separate run.
    func testLocalReleaseAppFivePeriodsTenMinutes() throws {
        let environment = ProcessInfo.processInfo.environment
        let enabled = environment["TM_REAL_LONG_UI"] ?? environment["TEST_RUNNER_TM_REAL_LONG_UI"]
        guard enabled == "1" else { throw XCTSkip("Set TM_REAL_LONG_UI=1 explicitly for the local five-period, 50-minute acceptance.") }
        let ci = [environment["CI"], environment["GITHUB_ACTIONS"]].compactMap { $0?.lowercased() }
        guard !ci.contains(where: { ["1", "true", "yes"].contains($0) }), environment["XCODE_CLOUD_WORKFLOW_ID"] == nil else {
            throw XCTSkip("Long hardware acceptance must not run in CI.")
        }
        let paths = [environment["TM_REAL_APP_PATH"], environment["TEST_RUNNER_TM_REAL_APP_PATH"]].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        let path = try XCTUnwrap(paths.first { !$0.isEmpty }, "An explicit, already built formal Release app path is required.")
        let hold = environment["TM_REAL_LONG_HOLD_SECONDS"] ?? environment["TEST_RUNNER_TM_REAL_LONG_HOLD_SECONDS"] ?? "30"
        XCTAssertEqual(Int(hold), 30, "The final SQLite collection window is fixed at 30 seconds.")
        executionTimeAllowance = 4200
        let appURL = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        let bundle = try XCTUnwrap(Bundle(url: appURL))
        XCTAssertEqual(bundle.bundleIdentifier, "io.github.sisyphe550.TemperatureMonitor")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: appURL.appendingPathComponent("Contents/MacOS/SensorWorker").path))
        let user = try XCTUnwrap(getpwuid(getuid()))
        let sessionsRoot = URL(fileURLWithPath: String(cString: user.pointee.pw_dir), isDirectory: true)
            .appendingPathComponent("Library/Application Support/io.github.sisyphe550.TemperatureMonitor/Sessions", isDirectory: true)
        let app = XCUIApplication(url: appURL)
        XCTAssertEqual(app.state, .notRunning, "Normally quit the previous real session before beginning this run.")
        let previousSessions = try realSessionNames(in: sessionsRoot)
        app.launchArguments = []
        addTeardownBlock {
            await MainActor.run {
                guard app.state != .notRunning else { return }
                FileHandle.standardOutput.write(Data("LONG_UI_FINAL_SNAPSHOT failure_cleanup hold_seconds=30\n".utf8))
                for seconds in [20.0, 10.0] { Thread.sleep(forTimeInterval: seconds) }
                if !app.windows["温度监测"].exists { XCTAssertTrue(NSWorkspace.shared.open(appURL)) }
                let quit = app.buttons["app.quit"]
                if quit.waitForExistence(timeout: 5) { quit.click() }
                XCTAssertTrue(app.wait(for: .notRunning, timeout: 10), "Normal failure cleanup did not finish; no force terminate was sent.")
            }
        }
        app.launch()
        let dashboard = app.windows["温度监测"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10), "Formal production launch must show the dashboard without --ui-open.")
        let status = app.menuBars.statusItems["status.temperature"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(realWaitUntil(timeout: 20) { self.realHasTemperature(self.statusValue(from: status)) })
        let picker = app.popUpButtons["cpu.period"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(realWaitUntil(timeout: 5) { ((try? self.realSessionNames(in: sessionsRoot)) ?? []).subtracting(previousSessions).count == 1 })
        let createdSessions = try realSessionNames(in: sessionsRoot).subtracting(previousSessions)
        let sessionName = try XCTUnwrap(createdSessions.first)
        let sessionDirectory = sessionsRoot.appendingPathComponent(sessionName, isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionDirectory.appendingPathComponent("monitor.sqlite").path))
        let utc = ISO8601DateFormatter()
        utc.timeZone = TimeZone(secondsFromGMT: 0)
        utc.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var timebase = mach_timebase_info_data_t()
        XCTAssertEqual(mach_timebase_info(&timebase), KERN_SUCCESS)
        var records: [[String: Any]] = []
        var durations: [Double] = []
        func record(_ event: String, _ details: [String: Any] = [:]) throws {
            var item: [String: Any] = ["event": event, "utc": utc.string(from: Date()),
                "awake_uptime_seconds": ProcessInfo.processInfo.systemUptime,
                "continuous_monotonic_seconds": Double(mach_continuous_time()) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000,
                "session_id": sessionName, "app_path": appURL.path]
            item.merge(details) { _, new in new }
            records.append(item)
            let data = try JSONSerialization.data(withJSONObject: item, options: [.sortedKeys])
            FileHandle.standardOutput.write(Data((event + " " + String(decoding: data, as: UTF8.self) + "\n").utf8))
        }
        try record("LONG_UI_BEGIN", ["periods_ms": [50, 100, 200, 500, 1000], "required_awake_seconds_per_period": 600,
            "launch_arguments": [], "status_exists": status.exists, "status_is_hittable": status.isHittable,
            "scope": "Formal Release; no fixture; OS sleep/wake, SQL cadence, worker read-batch/skipped rates and display-delay percentiles require independent evidence."])
        realScreenshot(dashboard, name: "LONG_UI-production-startup-dashboard")
        for milliseconds in [50, 100, 200, 500, 1000] {
            let label = "\(milliseconds) ms"
            picker.click()
            app.menuItems[label].click()
            XCTAssertTrue(realWaitUntil(timeout: 5) { picker.value as? String == label })
            let began = ProcessInfo.processInfo.systemUptime
            let beganUTC = utc.string(from: Date())
            try record("LONG_UI_PHASE_START", ["period_ms": milliseconds, "selected": picker.value as? String ?? "", "start_utc": beganUTC, "start_awake_uptime_seconds": began])
            while ProcessInfo.processInfo.systemUptime - began < 600 {
                let remaining = max(0, 600 - (ProcessInfo.processInfo.systemUptime - began))
                Thread.sleep(forTimeInterval: min(20, remaining))
                XCTAssertNotEqual(app.state, .notRunning)
                // Bring this owned App forward before requesting an AX snapshot.
                // Read each value once: separate snapshots can be invalidated by
                // another application's permission dialog between assertions.
                app.activate()
                XCTAssertFalse(app.staticTexts["fatal.code"].exists)
                XCTAssertTrue(picker.waitForExistence(timeout: 5), "CPU picker is missing after activation.")
                let selectedPeriod = picker.value as? String ?? ""
                XCTAssertEqual(selectedPeriod, label)
                let temperature = statusValue(from: status)
                XCTAssertTrue(realHasTemperature(temperature), temperature)
                try record("LONG_UI_PROGRESS", ["period_ms": milliseconds, "selected": selectedPeriod,
                    "held_awake_seconds": ProcessInfo.processInfo.systemUptime - began, "status": temperature])
            }
            let held = ProcessInfo.processInfo.systemUptime - began
            XCTAssertGreaterThanOrEqual(held, 600)
            durations.append(held)
            try record("LONG_UI_PHASE_END", ["period_ms": milliseconds, "selected": picker.value as? String ?? "",
                "start_utc": beganUTC, "start_awake_uptime_seconds": began, "held_awake_seconds": held, "status": statusValue(from: status)])
            realScreenshot(dashboard, name: "LONG_UI-CPU-\(milliseconds)ms-after-600s")
            let phaseJSON = XCTAttachment(data: try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
            phaseJSON.name = "LONG_UI-through-\(milliseconds)ms-json"
            phaseJSON.lifetime = .keepAlways
            add(phaseJSON)
        }
        XCTAssertEqual(durations.count, 5)
        XCTAssertGreaterThanOrEqual(durations.reduce(0, +), 3000)
        XCTAssertEqual(try realSessionNames(in: sessionsRoot).subtracting(previousSessions), createdSessions)
        try record("LONG_UI_FINAL_SNAPSHOT", ["hold_seconds": 30, "selected": picker.value as? String ?? "", "database_path": sessionDirectory.appendingPathComponent("monitor.sqlite").path])
        for seconds in [20.0, 10.0] {
            Thread.sleep(forTimeInterval: seconds)
            try record("LONG_UI_HOLD_PROGRESS", ["hold_chunk_seconds": seconds, "selected": picker.value as? String ?? ""])
        }
        realScreenshot(dashboard, name: "LONG_UI-final-before-normal-quit")
        let quit = app.buttons["app.quit"]
        XCTAssertTrue(quit.waitForExistence(timeout: 5))
        quit.click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sessionDirectory.path))
        XCTAssertTrue(try realSessionNames(in: sessionsRoot).subtracting(previousSessions).isEmpty)
        try record("LONG_UI_COMPLETE", ["period_held_awake_seconds": durations, "total_period_awake_seconds": durations.reduce(0, +), "normal_quit": true, "created_session_removed": true])
        let json = XCTAttachment(data: try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        json.name = "LONG_UI-five-periods-600s-and-normal-cleanup-json"
        json.lifetime = .keepAlways
        add(json)
    }

    private func realSessionNames(in root: URL) throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let directories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        return Set(try directories.filter { try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true && UUID(uuidString: $0.lastPathComponent) != nil }.map(\.lastPathComponent))
    }

    private func realWaitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        repeat {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.2)
        } while ProcessInfo.processInfo.systemUptime < deadline
        return condition()
    }

    private func realHasTemperature(_ text: String) -> Bool {
        text.range(of: #"^[0-9]+(?:\.[0-9]+)? °C$"#, options: .regularExpression) != nil
    }

    private func realText(_ element: XCUIElement) -> String {
        (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    }

    private func realScreenshot(_ element: XCUIElement, name: String) {
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
