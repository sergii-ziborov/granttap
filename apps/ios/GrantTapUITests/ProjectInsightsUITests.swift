import XCTest

/// Dedicated simulator fixtures only; never launch the Mac app in demo mode.
final class ProjectInsightsUITests: XCTestCase {
    func testHealthRefreshDistinguishesAnUnavailableRouteAndAllowsRetry() {
        continueAfterFailure = false
        let app = project()
        let health = app.buttons["project.health"]
        for _ in 0..<5 where !health.exists { app.swipeUp() }
        XCTAssertTrue(health.waitForExistence(timeout: 10))
        health.tap()
        let refresh = app.buttons["health.code-towers.refresh"]
        for _ in 0..<5 where !refresh.exists { app.swipeUp() }
        XCTAssertTrue(refresh.waitForExistence(timeout: 10))
        refresh.tap()
        XCTAssertTrue(app.staticTexts["No connected computer can receive this Mesh's analysis request."]
            .waitForExistence(timeout: 10))
        XCTAssertTrue(refresh.isEnabled)
    }

    func testStatisticsAndItsDrilldownUseTheSameTasksOnPhoneAndPad() {
        continueAfterFailure = false
        let app = project()
        let statistics = app.buttons["project.statistics"]
        for _ in 0..<5 where !statistics.exists { app.swipeUp() }
        XCTAssertTrue(statistics.waitForExistence(timeout: 10))
        statistics.tap()
        let chart = app.buttons["statistics.tasks.chart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Activity and evidence"].exists)
        chart.tap()
        XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["No Tasks in this bounded projection."].exists)
    }

    private func project() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_CAPTURE_TAB": "projects",
                                 "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let row = app.buttons["projects.row.granttap-project-demo"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        return app
    }
}
