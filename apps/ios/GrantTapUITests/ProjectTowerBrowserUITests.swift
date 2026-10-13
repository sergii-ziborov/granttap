import XCTest

final class ProjectTowerBrowserUITests: XCTestCase {
    func testSearchingLastSectionAndNoMatchUsesTheActualReportedSymbol() {
        let app = openTowers()
        app.buttons["code-towers.files"].tap()
        let search = app.textFields["code-towers.browser.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("missing-symbol")
        XCTAssertTrue(app.staticTexts["No matching files or sections."].exists)
        app.buttons["Clear search"].tap()
        search.tap(); search.typeText("healthSection36")
        let last = app.buttons["code-towers.browser.section.health-section-36"]
        XCTAssertTrue(last.waitForExistence(timeout: 5)); last.tap()
        XCTAssertTrue(app.staticTexts["code-towers.section-details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["healthSection36"].exists)
        XCTAssertTrue(app.staticTexts["360"].exists)
    }

    func testScrollableSectionsAndDirectedLinksKeepTheirActualDestination() {
        let app = openTowers()
        app.buttons["code-towers.files"].tap()
        app.buttons["code-towers.file.apps/ios/GrantTap/HealthView.swift"].tap()
        app.buttons["code-towers.sections"].tap()
        let last = app.buttons["code-towers.section.health-section-36"]
        let list = app.scrollViews["code-towers.section-list"]
        for _ in 0..<18 where !last.isHittable { list.swipeUp() }
        XCTAssertTrue(last.isHittable); last.tap()
        XCTAssertTrue(app.staticTexts["code-towers.section-details"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["code-towers.links"].tap()
        let link = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "code-towers.link.")).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap()
        XCTAssertTrue(app.staticTexts["code-towers.inspector.path"].exists || app.staticTexts["code-towers.inspector.external"].exists)
        app.buttons["code-towers.health"].tap()
        let facts = app.staticTexts["Coverage, complexity and unused-code findings are not reported in this map."]
        for _ in 0..<4 where !facts.exists { app.scrollViews["code-towers.health-scroll"].swipeUp() }
        XCTAssertTrue(facts.exists)
    }

    func testViewSettingsKeepCameraAndHelpExplainsActualGestures() {
        let app = openTowers()
        app.buttons["code-towers.zoom-in"].tap()
        let scene = app.descendants(matching: .any)["code-towers.scene"].firstMatch
        let before = scene.value as? String
        app.buttons["Graph view options"].tap()
        app.buttons["View settings"].tap()
        XCTAssertTrue(app.switches["code-towers.labels"].waitForExistence(timeout: 5))
        app.switches["code-towers.labels"].tap()
        app.switches["code-towers.auto-focus"].tap()
        app.descendants(matching: .any)["code-towers.color-mode"].firstMatch.tap()
        app.buttons["Kind"].tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(scene.value as? String, before)
        app.buttons["Graph view options"].tap()
        app.buttons["Graph controls"].tap()
        XCTAssertTrue(app.staticTexts["Scroll Sections to reach every reported symbol."].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["Graph view options"].tap()
        app.buttons["Hide graph panels"].tap()
        XCTAssertTrue(app.buttons["Show graph panels"].waitForExistence(timeout: 5))
        app.buttons["Show graph panels"].tap()
        XCTAssertTrue(app.buttons["code-towers.files"].exists)
    }

    private func openTowers() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_CAPTURE_TAB": "projects",
            "GRANTTAP_TEST_TOWER_SECTIONS": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let project = app.buttons["projects.row.granttap-project-demo"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let health = app.buttons["project.health"]
        for _ in 0..<5 where !health.exists { app.swipeUp() }
        health.tap()
        let towers = app.buttons["health.code-towers.github.com/sergii-ziborov/granttap"]
        for _ in 0..<5 where !towers.exists { app.swipeUp() }
        XCTAssertTrue(towers.waitForExistence(timeout: 10)); towers.tap()
        XCTAssertTrue(app.buttons["code-towers.files"].waitForExistence(timeout: 5))
        return app
    }
}
