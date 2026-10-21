import XCTest

final class ProjectTowerPreferencesUITests: XCTestCase {
    func testLegendIsIndependentAndHealthExplainsMeasuredFunctionChecks() {
        continueAfterFailure = false
        let app = CodeCityJourney.openTowers()
        CodeCityJourney.search("healthSection36", in: app)
        app.webViews.buttons["healthSection36 · L360"].firstMatch.tap()
        CodeCityJourney.control("Health details", in: app).tap()
        XCTAssertTrue(app.webViews.staticTexts["Code checks need review"].waitForExistence(timeout: 5))
        CodeCityJourney.control("Legend", in: app).tap()
        XCTAssertTrue(app.webViews.staticTexts["Opening this legend does not change filters."].exists)
        CodeCityJourney.capture("Code city independent legend", in: self)
        CodeCityJourney.control("Close legend", in: app).tap()
        XCTAssertTrue(app.webViews.staticTexts["Health evidence"].exists)
        CodeCityJourney.capture("Measured function checks with source provenance", in: self)
        CodeCityJourney.control("View settings", in: app).tap()
        XCTAssertTrue(CodeCityJourney.control("Reset view settings", in: app).exists)
        CodeCityJourney.capture("Code city display preferences", in: self)
        CodeCityJourney.selectCodeCheckColours(in: app)
        CodeCityJourney.capture("Code city measured-check colour settings", in: self)
        CodeCityJourney.control("Close settings", in: app).tap()
        XCTAssertTrue(app.webViews.staticTexts["Health evidence"].exists)
        CodeCityJourney.capture("Measured review highlight in code-check mode", in: self)
    }
}
