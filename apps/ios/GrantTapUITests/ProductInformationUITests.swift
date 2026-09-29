import XCTest

final class ProductInformationUITests: XCTestCase {
    func testTermsAndHelpOpenInsideSettingsAndReturnToAbout() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        app.buttons["Settings"].firstMatch.tap()
        let about = app.buttons["About GrantTap"].firstMatch
        reveal(about, in: app)
        about.tap()
        XCTAssertTrue(app.navigationBars["About GrantTap"].waitForExistence(timeout: 10))
        let terms = app.buttons["information.terms"].firstMatch
        reveal(terms, in: app)
        terms.tap()
        XCTAssertTrue(app.staticTexts["Agreement and license"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Terms of Use"].waitForExistence(timeout: 10),
                      app.navigationBars.debugDescription)
        app.navigationBars["Terms of Use"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["About GrantTap"].waitForExistence(timeout: 10))
        let help = app.buttons["information.help"].firstMatch
        reveal(help, in: app)
        help.tap()
        XCTAssertTrue(app.staticTexts["Mac app and device connections"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["information.learn"].exists)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 where !fullyVisible(element, in: app) { app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(fullyVisible(element, in: app))
    }

    private func fullyVisible(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let frame = element.frame
        return frame.width > 0 && frame.height > 0 && app.frame.insetBy(dx: 0, dy: 90).contains(frame)
    }
}
