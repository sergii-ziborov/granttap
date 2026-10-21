import XCTest

/// The expanded received report exercises the same renderer as a normal Mesh.
enum DenseCodeCityJourney {
    private static let sourcePath = "apps/ios/GrantTap/Features/Area25/Source649.swift"

    static func run(in test: XCTestCase) {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = openDenseInspector(in: test)

        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.webViews.firstMatch.frame.width > app.webViews.firstMatch.frame.height
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 10), .completed)
        assertInspector(app)
        assertCameraControls(app)
        capture(app, "Dense650 — landscape source inspector", in: test)
        app.webViews.buttons["Fit"].firstMatch.tap()
        XCTAssertFalse(app.webViews.buttons["Close details"].firstMatch.exists)
        capture(app, "Dense650 — landscape overview", in: test)
        openLastSource(app)
        assertInspector(app)
        capture(app, "Dense650 — landscape source selected again", in: test)
        app.buttons["Close code towers"].tap()
        XCTAssertTrue(app.navigationBars["Health"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Current · partial report"].exists)
    }

    static func openDenseInspector(in test: XCTestCase) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = openHealth()
        capture(app, "Dense650 — Health partial report", in: test)
        app.buttons["health.code-towers.github.com/sergii-ziborov/granttap"].tap()
        CodeCityJourney.waitForViewer(app)
        app.webViews.buttons["Fit"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "650/653"))
            .firstMatch.exists)
        assertCameraControls(app)
        capture(app, "Dense650 — portrait overview", in: test)
        openLastSource(app)
        assertInspector(app)
        capture(app, "Dense650 — portrait source inspector", in: test)
        return app
    }

    private static func openHealth() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_CAPTURE_TAB": "projects",
            "GRANTTAP_TEST_LANGUAGE": "en", "GRANTTAP_TEST_GRAPH_LARGE": "1"]
        app.launch()
        let project = app.buttons["projects.row.granttap-project-demo"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let health = app.buttons["project.health"]
        for _ in 0..<5 where !health.isHittable { app.swipeUp() }
        XCTAssertTrue(health.isHittable); health.tap()
        XCTAssertTrue(app.staticTexts["Current · partial report"].waitForExistence(timeout: 10))
        let towers = app.buttons["health.code-towers.github.com/sergii-ziborov/granttap"]
        XCTAssertTrue(towers.waitForExistence(timeout: 10))
        return app
    }

    private static func openLastSource(_ app: XCUIApplication) {
        CodeCityJourney.search("Source649", in: app)
        let file = app.webViews.buttons[sourcePath]
        XCTAssertTrue(file.waitForExistence(timeout: 10)); file.tap()
        XCTAssertTrue(app.webViews.staticTexts[sourcePath].waitForExistence(timeout: 10))
    }

    private static func assertInspector(_ app: XCUIApplication) {
        let viewport = app.webViews.firstMatch.frame.insetBy(dx: -1, dy: -1)
        for name in ["Close details", "Sections", "Links", "Health"] {
            let control = CodeCityJourney.control(name, in: app)
            XCTAssertTrue(control.isHittable, name)
            XCTAssertTrue(viewport.contains(control.frame), name)
        }
    }

    private static func assertCameraControls(_ app: XCUIApplication) {
        let viewport = app.webViews.firstMatch.frame.insetBy(dx: -1, dy: -1)
        for name in ["Files", "Fit", "Zoom in", "Zoom out", "Top", "ISO", "Full screen"] {
            let control = app.webViews.buttons[name].firstMatch
            XCTAssertTrue(control.isHittable, name)
            XCTAssertTrue(viewport.contains(control.frame), name)
        }
    }

    private static func capture(_ app: XCUIApplication, _ name: String, in test: XCTestCase) {
        // App-only captures on iOS 26 crop a rotated window using portrait bounds.
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; test.add(image)
        if name.contains("portrait") {
            let viewport = XCTAttachment(screenshot: app.webViews.firstMatch.screenshot())
            viewport.name = name + " — viewer viewport"; viewport.lifetime = .keepAlways; test.add(viewport)
        }
    }
}
