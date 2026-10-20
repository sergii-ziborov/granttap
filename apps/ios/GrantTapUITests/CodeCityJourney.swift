import XCTest

/// Public controls shared by phone and Mac's offline Repo Lens workspace.
enum CodeCityJourney {
    static func control(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    static func waitForViewer(_ app: XCUIApplication) {
        XCTAssertTrue(app.webViews.buttons["Files"].firstMatch.waitForExistence(timeout: 20))
    }

    static func search(_ text: String, in app: XCUIApplication) {
        let search = app.webViews.searchFields.firstMatch
        if !app.webViews.buttons["Close files"].firstMatch.exists {
            app.webViews.buttons["Files"].firstMatch.tap()
        }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let clear = app.webViews.buttons["Clear search"].firstMatch
        if clear.isHittable { clear.tap() }
        search.tap()
        // iOS can introduce its keyboard preview on the first landscape input.
        let keyboardWelcome = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Continue"]
        if keyboardWelcome.waitForExistence(timeout: 1), keyboardWelcome.isHittable { keyboardWelcome.tap() }
        // Submit the filter before selecting: the landscape keyboard covers result rows.
        search.typeText(text + "\n")
    }

    static func capture(_ name: String, in test: XCTestCase) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; test.add(image)
    }

    static func openTowers(sections: Bool = true, renderFailure: Bool = false) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_CAPTURE_TAB": "projects",
            sections ? "GRANTTAP_TEST_TOWER_SECTIONS" : "GRANTTAP_TEST_GRAPH": "1",
            "GRANTTAP_TEST_LANGUAGE": "en"]
        if renderFailure { app.launchEnvironment["GRANTTAP_TEST_GRAPH_RENDER_FAILURE"] = "1" }
        app.launch()
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.height > app.frame.width
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 5), .completed)
        let project = app.buttons["projects.row.granttap-project-demo"]
        XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
        let health = app.buttons["project.health"]
        for _ in 0..<5 where !health.exists { app.swipeUp() }
        health.tap()
        let towers = app.buttons["health.code-towers.github.com/sergii-ziborov/granttap"]
        for _ in 0..<5 where !towers.exists { app.swipeUp() }
        XCTAssertTrue(towers.waitForExistence(timeout: 10)); towers.tap()
        if renderFailure {
            XCTAssertTrue(app.buttons["Retry code city"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["code-towers.files"].waitForExistence(timeout: 10))
        } else { waitForViewer(app) }
        return app
    }

    static func scrollSections(in app: XCUIApplication, until target: XCUIElement) {
        let web = app.webViews.firstMatch
        func visible() -> Bool {
            guard target.exists else { return false }
            let panel = app.webViews.descendants(matching: .any).matching(
                NSPredicate(format: "label BEGINSWITH %@", "Tower details")).firstMatch.frame
            return target.isHittable && target.frame.minY > control("Sections", in: app).frame.maxY
                && target.frame.maxY < panel.maxY - 8
        }
        for _ in 0..<18 where !visible() {
            let start = web.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.72))
            let end = web.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.38))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(visible(), "The requested evidence must be inside the visible inspector")
    }
}
