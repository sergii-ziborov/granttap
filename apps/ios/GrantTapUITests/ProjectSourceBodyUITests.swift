import XCTest

final class ProjectSourceBodyUITests: XCTestCase {
    func testMeasuredSourceBodyDoesNotInventSectionsAndKeepsTheInspectorUsable() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_CAPTURE_TAB": "projects",
            "GRANTTAP_TEST_GRAPH_SOURCE_BODY": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let project = app.buttons["projects.row.granttap-project-demo"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let health = app.buttons["project.health"]
        for _ in 0..<5 where !health.exists { app.swipeUp() }
        health.tap()
        let towers = app.buttons["health.code-towers.github.com/sergii-ziborov/granttap"]
        for _ in 0..<5 where !towers.exists { app.swipeUp() }
        XCTAssertTrue(towers.waitForExistence(timeout: 10)); towers.tap()
        CodeCityJourney.waitForViewer(app)
        CodeCityJourney.search("Context.rs", in: app)
        let source = app.webViews.buttons["src/Context.rs"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5)); source.tap()
        let sections = app.webViews.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "CONTEXT_LIMIT_"))
        XCTAssertTrue(sections.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(sections.count, 3, "The neutral source body must not be a fourth reported symbol")
        CodeCityJourney.capture("Measured body and three actual constants", in: self)
        sections.firstMatch.tap()
        XCTAssertTrue(app.webViews.staticTexts["constant"].firstMatch.waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 10), .completed)
        for label in ["Sections", "Links", "Health", "Close details"] {
            XCTAssertTrue(CodeCityJourney.control(label, in: app).isHittable)
        }
        CodeCityJourney.capture("Measured source body landscape", in: self)
        XCUIDevice.shared.orientation = .portrait
    }
}
