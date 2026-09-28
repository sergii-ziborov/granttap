import XCTest

final class UsageUITests: XCTestCase {
    func testSkillFilterKeepsOverviewAndOpensUsageStatistics() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_CAPTURE_TAB": "usage",
                                 "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let calls = app.buttons["usage.open-tool-calls"]
        XCTAssertTrue(calls.waitForExistence(timeout: 10))
        let overview = calls.label
        let skills = app.segmentedControls.buttons["Skills"]
        for _ in 0..<5 where !skills.isHittable { app.swipeUp() }
        XCTAssertTrue(skills.exists)
        skills.tap()
        for _ in 0..<5 where !calls.isHittable { app.swipeDown() }
        XCTAssertEqual(calls.label, overview, "the tool filter leaves the period overview intact")
        let used = app.buttons["usage.open-skills-used"]
        XCTAssertTrue(used.isHittable)
        used.tap()
        XCTAssertTrue(app.navigationBars["Skills used"].waitForExistence(timeout: 10))
        let documentSkill = app.buttons.containing(.staticText, identifier: "documents").firstMatch
        XCTAssertTrue(documentSkill.waitForExistence(timeout: 10))
        documentSkill.tap()
        XCTAssertTrue(app.staticTexts["Observed usage"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Calls"].exists)
        XCTAssertTrue(app.staticTexts["CPU time"].exists)
        XCTAssertTrue(app.staticTexts["Peak memory"].exists)
        let history = app.staticTexts["Call history"]
        for _ in 0..<4 where !history.isHittable { app.swipeUp() }
        XCTAssertTrue(history.exists)
        XCTAssertFalse(app.staticTexts["No calls recorded yet."].exists)
        add(XCTAttachment(screenshot: app.screenshot()))
    }
}
