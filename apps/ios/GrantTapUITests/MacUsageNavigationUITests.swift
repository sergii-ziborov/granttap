#if targetEnvironment(macCatalyst)
import XCTest

final class MacUsageNavigationUITests: XCTestCase {
    func testReselectingUsageKeepsThePeriodAndSidebarSwitchesRemainResponsive() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_TEST_LANGUAGE": "en",
            "GRANTTAP_TEST_USAGE_LOAD": "1"]
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO"]
        app.launch()
        app.activate()
        let usage = app.buttons["sidebar.usage"]
        XCTAssertTrue(usage.waitForExistence(timeout: 15))
        var times: [String: Double] = [:]
        for tab in ["usage", "projects", "tasks", "usage", "now", "usage"] {
            let start = ProcessInfo.processInfo.systemUptime
            let button = app.buttons["sidebar.\(tab)"]
            button.click()
            let selected = expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: button)
            wait(for: [selected], timeout: 3)
            times["\(times.count)-\(tab)"] = ProcessInfo.processInfo.systemUptime - start
        }
        let evidence = XCTAttachment(string: String(describing: times))
        evidence.name = "Mac sidebar transition seconds including UI automation"
        evidence.lifetime = .keepAlways
        add(evidence)
        XCTAssertLessThan(times.values.max() ?? 0, 3)
        app.buttons["usage.open-tool-calls"].click()
        XCTAssertTrue(app.buttons["page.back"].waitForExistence(timeout: 5))
        app.buttons["sidebar.now"].click()
        XCTAssertFalse(app.buttons["page.back"].exists, "Changing tabs must leave a usage drilldown.")
        usage.click()
        XCTAssertTrue(app.buttons["usage.open-tool-calls"].waitForExistence(timeout: 5))
        let hour = app.segmentedControls.buttons["1h"]
        XCTAssertTrue(hour.waitForExistence(timeout: 5))
        hour.click()
        XCTAssertTrue(hour.isSelected)
        usage.click()
        XCTAssertTrue(hour.isSelected, "A sidebar click must preserve the current page's period instead of rebuilding navigation.")
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Usage after repeated sidebar navigation"
        image.lifetime = .keepAlways
        add(image)
        app.terminate()
    }
}
#endif
