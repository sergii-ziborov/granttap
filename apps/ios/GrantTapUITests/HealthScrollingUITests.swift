import XCTest

final class HealthScrollingUITests: XCTestCase {
    func testHealthScrollAndBackRemainResponsiveDuringMultiMeshPersistence() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_CAPTURE_TAB": "projects",
            "GRANTTAP_TEST_LANGUAGE": "en", "GRANTTAP_TEST_MESH_STREAM": "1"]
        app.launch()
        let project = app.buttons["projects.row.granttap-project-demo"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let health = app.buttons["project.health"]
        for _ in 0..<5 where !health.isHittable { app.swipeUp() }
        XCTAssertTrue(health.isHittable)
        health.tap()
        let scroll = app.collectionViews["health.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        let started = Date()
        for _ in 0..<3 { scroll.swipeUp() }
        for _ in 0..<3 { scroll.swipeDown() }
        XCTAssertLessThan(Date().timeIntervalSince(started), 20,
                          "Health gestures must finish while the archive is continuously written")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(health.waitForExistence(timeout: 5))
    }
}
