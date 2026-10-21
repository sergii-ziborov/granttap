import XCTest

final class ProjectCodeCityRecoveryUITests: XCTestCase {
    func testRenderingFailureRetainsSourceSearchSectionsLinksAndHealth() {
        continueAfterFailure = false
        let app = CodeCityJourney.openTowers(renderFailure: true)
        let scene = app.descendants(matching: .any)["code-towers.scene"].firstMatch
        XCTAssertTrue(scene.exists)
        CodeCityJourney.capture("Code city recovery — native fallback overview", in: self)
        for action in ["zoom-in", "zoom-out", "fit"] { app.buttons["code-towers.\(action)"].tap() }
        let search = app.textFields["code-towers.search"]
        search.tap(); search.typeText("HealthView")
        let source = app.buttons["code-towers.file.apps/ios/GrantTap/HealthView.swift"]
        XCTAssertTrue(source.waitForExistence(timeout: 5)); source.tap()
        XCTAssertTrue(app.staticTexts["code-towers.inspector.path"].waitForExistence(timeout: 5))
        app.buttons["code-towers.inspector.focus"].tap()
        app.buttons["code-towers.sections"].tap()
        XCTAssertTrue(app.buttons["code-towers.section.health-section-1"].waitForExistence(timeout: 5))
        app.buttons["code-towers.links"].tap()
        let link = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "code-towers.link.")).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap()
        app.buttons["code-towers.health"].tap()
        let facts = app.staticTexts["Test coverage and runtime performance were not measured."]
        for _ in 0..<5 where !facts.exists { app.scrollViews["code-towers.health-scroll"].swipeUp() }
        XCTAssertTrue(facts.exists)
        app.buttons["Close file details"].tap()
        search.tap(); search.typeText("healthSection36")
        let section = app.buttons["code-towers.search.section.health-section-36"]
        XCTAssertTrue(section.waitForExistence(timeout: 5)); section.tap()
        XCTAssertTrue(app.staticTexts["code-towers.section-details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["healthSection36"].exists)
        XCTAssertTrue(app.staticTexts["360"].exists)
        CodeCityJourney.capture("Code city recovery — selected section evidence", in: self)
        app.buttons["Done"].tap()
        app.buttons["Close file details"].tap()
        app.buttons["Graph view options"].tap(); app.buttons["View settings"].tap()
        XCTAssertTrue(app.switches["code-towers.labels"].waitForExistence(timeout: 5))
        app.switches["code-towers.labels"].tap()
        app.buttons["Done"].tap()
        app.buttons["Graph view options"].tap(); app.buttons["Graph controls"].tap()
        XCTAssertTrue(app.staticTexts["Scroll Sections to reach every reported symbol."].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["Graph view options"].tap(); app.buttons["Hide graph panels"].tap()
        XCTAssertTrue(app.buttons["Show graph panels"].waitForExistence(timeout: 5))
        app.buttons["Show graph panels"].tap()
        XCTAssertTrue(app.buttons["Retry code city"].exists)
    }
}
