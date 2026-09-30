import XCTest

final class PasskeyConnectionUITests: XCTestCase {
    func testPasskeyConnectionOpensFromUnpairedWelcomeAndReturns() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()

        let passkey = app.buttons["Sign in with passkey"].firstMatch
        XCTAssertTrue(passkey.waitForExistence(timeout: 10))
        passkey.tap()

        XCTAssertTrue(app.navigationBars["Connect with passkey"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Create a GrantTap account"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(passkey.waitForExistence(timeout: 5))
    }
}
