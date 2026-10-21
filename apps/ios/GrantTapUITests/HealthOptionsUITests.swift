import XCTest

final class HealthOptionsUITests: XCTestCase {
    func testHealthOptionsFilterSortAndDiagnosticsCanBeResetWithoutRebuildingReports() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_CAPTURE_TAB": "projects",
            "GRANTTAP_TEST_GRAPH": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let project = app.buttons["projects.row.granttap-project-demo"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let health = app.buttons["project.health"]
        for _ in 0..<5 where !health.isHittable { app.swipeUp() }
        health.tap()
        app.buttons["health.options"].tap()
        XCTAssertTrue(app.navigationBars["Health options"].waitForExistence(timeout: 5))
        app.buttons["Reset Health options"].tap()
        app.buttons["health.options.filter"].tap()
        app.buttons["Errors only"].tap()
        app.buttons["health.options.sort"].tap()
        app.buttons["Name"].tap()
        let diagnostics = app.switches["health.options.diagnostics"]
        diagnostics.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(diagnostics.value as? String, "1")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["No repositories match these options."].waitForExistence(timeout: 5))
        CodeCityJourney.capture("Health compact status and filtered reports", in: self)
        let showAll = app.buttons["health.options.show-all"]
        XCTAssertTrue(showAll.exists); showAll.tap()
        XCTAssertTrue(app.buttons["health.code-towers.github.com/sergii-ziborov/granttap"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["No repositories match these options."].exists)
        app.buttons["health.options"].tap()
        app.buttons["Reset Health options"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["health.code-towers.github.com/sergii-ziborov/granttap"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["No repositories match these options."].exists)
        CodeCityJourney.capture("Health available reports with options", in: self)
        app.terminate(); app.launch()
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        for _ in 0..<5 where !health.isHittable { app.swipeUp() }
        health.tap()
        XCTAssertTrue(app.buttons["health.code-towers.github.com/sergii-ziborov/granttap"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["No repositories match these options."].exists)
        XCTAssertFalse(app.descendants(matching: .any)["health.diagnostics"].exists)
    }
}
