import XCTest

final class ProjectTowerControlsUITests: XCTestCase {
    func testTowerCameraControlsAndScrollableSectionsOpenEvidenceDetails() {
        continueAfterFailure = false
        let app = CodeCityJourney.openTowers()
        app.webViews.buttons["Fit"].firstMatch.tap()
        let overview = XCTAttachment(screenshot: app.screenshot())
        overview.name = "Repo Lens overview fitted to the phone"
        overview.lifetime = .keepAlways
        add(overview)
        for control in ["Zoom in", "Zoom out", "Top", "ISO", "Fit"] {
            let button = app.webViews.buttons[control].firstMatch
            XCTAssertTrue(button.isHittable); button.tap()
        }
        let orbit = CodeCityJourney.control("Orbit", in: app)
        let nextMode = orbit.exists ? "Pan" : "Orbit"
        (orbit.exists ? orbit : CodeCityJourney.control("Pan", in: app)).tap()
        XCTAssertTrue(CodeCityJourney.control(nextMode, in: app).exists)
        CodeCityJourney.search("healthSection36", in: app)
        let section = app.webViews.buttons["healthSection36 · L360"]
        XCTAssertTrue(section.waitForExistence(timeout: 5)); section.tap()
        XCTAssertTrue(app.webViews.staticTexts["Observed source"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.webViews.staticTexts["healthSection36"].firstMatch.exists)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Repo Lens tower section with received source evidence"
        image.lifetime = .keepAlways
        add(image)
    }

    func testCodeCityControlsAndDetailsRemainVisibleInLandscape() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = CodeCityJourney.openTowers()
        app.webViews.buttons["Fit"].firstMatch.tap()
        capture(app, "Repo Lens city — portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = NSPredicate { _, _ in
            app.webViews.firstMatch.frame.width > app.webViews.firstMatch.frame.height
        }
        expectation(for: rotated, evaluatedWith: app.webViews.firstMatch)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.webViews.buttons["Fit"].firstMatch.waitForExistence(timeout: 5))
        app.webViews.buttons["Fit"].firstMatch.tap()
        for label in ["Files", "Zoom in", "Zoom out", "Top", "ISO", "Full screen"] {
            let control = app.webViews.buttons[label].firstMatch
            XCTAssertTrue(control.isHittable, label)
            XCTAssertTrue(app.webViews.firstMatch.frame.insetBy(dx: -1, dy: -1).contains(control.frame), label)
        }
        capture(app, "Repo Lens city — landscape")
        CodeCityJourney.search("HealthView", in: app)
        app.webViews.buttons["apps/ios/GrantTap/HealthView.swift"].firstMatch.tap()
        CodeCityJourney.search("healthSection36", in: app)
        let section = app.webViews.buttons["healthSection36 · L360"]
        XCTAssertTrue(section.waitForExistence(timeout: 5)); section.tap()
        XCTAssertTrue(app.webViews.staticTexts["360–367"].waitForExistence(timeout: 5))
        for label in ["Close details", "Sections", "Links", "Health"] {
            XCTAssertTrue(CodeCityJourney.control(label, in: app).isHittable, label)
        }
        capture(app, "Repo Lens source inspector — landscape")
        app.webViews.buttons["Fit"].firstMatch.tap()
        XCTAssertFalse(app.webViews.buttons["Close details"].firstMatch.exists)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
