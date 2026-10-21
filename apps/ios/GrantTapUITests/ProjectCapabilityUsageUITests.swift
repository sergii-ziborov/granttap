import XCTest

final class ProjectCapabilityUsageUITests: XCTestCase {
    private func openTools() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_CAPTURE_TAB": "projects",
            "GRANTTAP_TEST_LANGUAGE": "en", "GRANTTAP_TEST_CAPABILITY_USAGE": "1"]
        app.launch()
        let project = app.buttons["projects.row.granttap-project-demo"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let tools = app.buttons["project.tools-skills"]
        for _ in 0..<8 where !tools.isHittable { app.swipeUp() }
        XCTAssertTrue(tools.waitForExistence(timeout: 5))
        tools.tap()
        XCTAssertTrue(app.navigationBars["Tools & Skills"].waitForExistence(timeout: 5))
        return app
    }

    func testRecordedUsageRemainsVisibleAfterRecentCallDetailsWereEvicted() {
        let app = openTools()
        let used = app.staticTexts["350 observed calls"]
        for _ in 0..<6 where !used.exists { app.swipeUp() }
        XCTAssertTrue(used.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Tools and recorded usage"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons.containing(.staticText, identifier: "code-review").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["code-review"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["350"].exists)
        XCTAssertTrue(app.buttons["project.capability.policy"].exists)
        let notice = app.staticTexts["The computer reported recorded use. Recent call details are not in this snapshot."]
        for _ in 0..<5 where !notice.exists { app.swipeUp() }
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
    }

    func testCapabilityRowNavigatesFromItsTrailingEdge() {
        let app = openTools()
        let link = app.buttons.containing(.staticText, identifier: "code-review").firstMatch
        let row = app.cells.containing(.staticText, identifier: "code-review").firstMatch
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isHittable)
        XCTAssertGreaterThan(link.frame.maxX, row.frame.maxX - 32)
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["code-review"].waitForExistence(timeout: 5))
    }

    func testObservedSkillsAppearWithoutInventingASharedBundle() {
        let app = openTools()
        let skill = app.buttons.containing(.staticText, identifier: "review-workflow").firstMatch
        for _ in 0..<6 where !skill.exists { app.swipeUp() }
        XCTAssertTrue(skill.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["12 observed calls"].exists)
        skill.tap()
        XCTAssertTrue(app.staticTexts["Observed in this Project"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Approve exact bundle"].exists)
    }
}
