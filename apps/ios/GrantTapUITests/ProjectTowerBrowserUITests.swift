import XCTest

final class ProjectTowerBrowserUITests: XCTestCase {
    func testSearchingLastSectionAndNoMatchUsesTheActualReportedSymbol() {
        continueAfterFailure = false
        let app = CodeCityJourney.openTowers()
        CodeCityJourney.search("missing-symbol", in: app)
        XCTAssertTrue(app.webViews.staticTexts["No matching files or symbols."].exists)
        CodeCityJourney.search("healthSection36", in: app)
        let last = app.webViews.buttons["healthSection36 · L360"]
        XCTAssertTrue(last.waitForExistence(timeout: 5)); last.tap()
        XCTAssertTrue(app.webViews.staticTexts["Observed source"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.webViews.staticTexts["healthSection36"].firstMatch.exists)
        XCTAssertTrue(app.webViews.staticTexts["360–367"].exists)
    }

    func testScrollableSectionsAndDirectedLinksKeepTheirActualDestination() {
        continueAfterFailure = false
        let app = CodeCityJourney.openTowers()
        CodeCityJourney.search("HealthView", in: app)
        app.webViews.buttons["apps/ios/GrantTap/HealthView.swift"].tap()
        let last = app.webViews.switches.matching(NSPredicate(format: "label CONTAINS %@", "healthSection36")).firstMatch
        CodeCityJourney.scrollSections(in: app, until: last)
        XCTAssertTrue(last.isHittable); last.tap()
        XCTAssertTrue(app.webViews.staticTexts["Observed source"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.webViews.staticTexts["360–367"].exists)
        CodeCityJourney.capture("Repo Lens — last reported section evidence", in: self)
        CodeCityJourney.control("Links", in: app).tap()
        let link = app.webViews.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "→")).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap()
        CodeCityJourney.capture("Repo Lens — directed link actual destination", in: self)
        CodeCityJourney.control("Health", in: app).tap()
        XCTAssertTrue(app.webViews.staticTexts["Health evidence"].waitForExistence(timeout: 5))
        let facts = app.webViews.staticTexts["Coverage and complexity were not reported. Section-size highlights use measured LOC."]
        CodeCityJourney.scrollSections(in: app, until: facts)
        XCTAssertTrue(facts.exists)
        CodeCityJourney.capture("Repo Lens — unreported health stays unknown", in: self)
    }

    func testViewSettingsKeepCameraAndHelpExplainsActualGestures() {
        continueAfterFailure = false
        let app = CodeCityJourney.openTowers()
        app.webViews.buttons["Zoom in"].firstMatch.tap()
        app.webViews.buttons["Highlights"].firstMatch.tap()
        let threshold = app.webViews.sliders["Section size threshold"]
        XCTAssertTrue(threshold.waitForExistence(timeout: 5))
        threshold.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).tap()
        app.webViews.buttons["Close settings"].firstMatch.tap()
        app.webViews.buttons["Help"].firstMatch.tap()
        XCTAssertTrue(app.webViews.staticTexts["Scroll Sections to reach every reported symbol."].waitForExistence(timeout: 5))
        app.webViews.buttons["Close help"].firstMatch.tap()
        app.webViews.buttons["Full screen"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Show graph panels"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.webViews.buttons["Files"].firstMatch.exists)
        app.buttons["Show graph panels"].tap()
        XCTAssertTrue(app.buttons["Close code towers"].exists)
    }
}
