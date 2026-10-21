import XCTest

final class ProjectArchitectureRelationsUITests: XCTestCase {
    func testGraphExpandsObservedRelationsWithComponentEvidence() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "GRANTTAP_DEMO": "1", "GRANTTAP_CAPTURE_TAB": "projects",
            "GRANTTAP_TEST_GRAPH": "1", "GRANTTAP_TEST_LANGUAGE": "en",
        ]
        app.launch()

        let project = app.buttons["projects.row.granttap-project-demo"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let graph = app.buttons["project.openGraph"]
        XCTAssertTrue(graph.waitForExistence(timeout: 10))
        graph.tap()

        let codeMap = app.buttons["architecture.towers.github.com/sergii-ziborov/granttap"]
        XCTAssertTrue(codeMap.waitForExistence(timeout: 5))
        XCTAssertTrue(codeMap.label.contains("Code map"), "The primary action describes files and functions")
        XCTAssertTrue(app.staticTexts["Report details"].exists)
        let menu = XCTAttachment(screenshot: app.screenshot())
        menu.name = "Graph — code map, architecture and report details"
        menu.lifetime = .keepAlways; add(menu)
        app.staticTexts["Report details"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Analysis fingerprint:")).firstMatch.exists)

        let relations = app.staticTexts["Relations in this report"]
        for _ in 0..<5 where !relations.exists { app.swipeUp() }
        XCTAssertTrue(relations.waitForExistence(timeout: 10))
        relations.tap()
        XCTAssertTrue(app.staticTexts["2 observed links"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["iPhone App"].exists)
        XCTAssertTrue(app.staticTexts["Engine"].exists)
    }
}
