import XCTest

final class SettingsNavigationUITests: XCTestCase {
    func testSettingsKeepsItsChildPagesAndReturnsToPersonalContent() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        reveal(settings, in: app)
        settings.tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        let company = app.buttons["settings.company-accounts"]
        reveal(company, in: app)
        company.tap()
        XCTAssertTrue(app.navigationBars["Company accounts"].waitForExistence(timeout: 10))
        app.navigationBars["Company accounts"].buttons.firstMatch.tap()

        let learn = app.buttons["settings.open-learn"]
        reveal(learn, in: app)
        learn.tap()
        XCTAssertTrue(app.navigationBars["Learn"].waitForExistence(timeout: 10))
        app.navigationBars["Learn"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["GrantTap"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Now"].firstMatch.isSelected)
        XCTAssertFalse(app.navigationBars["Settings"].exists)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
        // A tap during List deceleration stops scrolling instead of opening
        // the row. Wait for the visible row to settle before exercising it.
        var previousFrame = CGRect.null
        var stableSince = Date()
        let settled = expectation(for: NSPredicate { _, _ in
            let frame = element.frame
            if frame != previousFrame {
                previousFrame = frame
                stableSince = Date()
            }
            return element.isHittable && Date().timeIntervalSince(stableSince) >= 0.5
        }, evaluatedWith: element)
        wait(for: [settled], timeout: 5)
    }
}
