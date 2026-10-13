import XCTest

final class ProjectTowerControlsUITests: XCTestCase {
    func testTowerCameraControlsAndScrollableSectionsOpenEvidenceDetails() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_CAPTURE_TAB": "projects",
                                 "GRANTTAP_TEST_GRAPH": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let project = app.buttons["projects.row.granttap-project-demo"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let health = app.buttons["project.health"]
        for _ in 0..<5 where !health.exists { app.swipeUp() }
        health.tap()
        let towers = app.buttons["health.code-towers.github.com/sergii-ziborov/granttap"]
        for _ in 0..<5 where !towers.exists { app.swipeUp() }
        XCTAssertTrue(towers.waitForExistence(timeout: 10))
        towers.tap()
        let zoom = app.buttons["code-towers.zoom-in"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 5))
        let camera = app.descendants(matching: .any)["code-towers.scene"].firstMatch
        let before = camera.value as? String
        zoom.tap()
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(
            format: "value != %@", before ?? ""), object: camera)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed)
        app.buttons["code-towers.files"].tap()
        let file = app.buttons["code-towers.file.apps/ios/GrantTap/HealthView.swift"]
        XCTAssertTrue(file.waitForExistence(timeout: 5))
        file.tap()
        XCTAssertTrue(app.buttons["code-towers.sections"].waitForExistence(timeout: 5))
        app.buttons["code-towers.sections"].tap()
        let section = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "code-towers.section.")).firstMatch
        XCTAssertTrue(section.waitForExistence(timeout: 5))
        section.tap()
        XCTAssertTrue(app.staticTexts["code-towers.section-details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Observed source"].exists)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Selected tower section with source evidence"
        image.lifetime = .keepAlways
        add(image)
    }
}
