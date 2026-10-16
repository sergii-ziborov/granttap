#if targetEnvironment(macCatalyst)
import XCTest

final class MacTabFrameUITests: XCTestCase {
    func testSidebarReachesNextDisplayTickWithoutHalfSecondTransition() {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_TEST_LANGUAGE": "en",
            "GRANTTAP_TEST_TAB_FRAMES": "1", "GRANTTAP_TEST_USAGE_LOAD": "1"]
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.buttons["sidebar.usage"].waitForExistence(timeout: 15))
        var times: [String: Double] = [:]
        let tabs = ["usage", "projects", "tasks", "now", "devices", "settings"]
        for (index, tab) in (tabs + tabs).enumerated() {
            app.buttons["sidebar.\(tab)"].click()
            let probe = app.otherElements["debug.tab-frame"]
            let updated = expectation(for: NSPredicate { _, _ in
                (probe.value as? String)?.contains("|\(tab)|") == true
            }, evaluatedWith: probe)
            wait(for: [updated], timeout: 5)
            let fields = (probe.value as? String ?? "").split(separator: "|")
            guard fields.count == 3, let seconds = Double(fields[2]) else { XCTFail("Missing display timing"); return }
            times["\(times.count)-\(tab)"] = seconds
            // Cold native controls may initialize on first opening. Revisited
            // tabs have the tighter budget; neither may wait half a second.
            XCTAssertLessThan(seconds, index < tabs.count ? 0.3 : 0.2,
                "Selection to next display tick must not wait for a navigation animation or full list.")
        }
        let evidence = XCTAttachment(string: String(describing: times))
        evidence.name = "Sidebar action to first post-layout display tick, excluding XCTest click overhead"
        evidence.lifetime = .keepAlways
        add(evidence)
        app.terminate()
    }
}
#endif
