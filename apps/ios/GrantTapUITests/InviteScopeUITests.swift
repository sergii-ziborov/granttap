import XCTest

final class InviteScopeUITests: XCTestCase {
    func testLinkedComputerQRShowsItsActualScopeAndOfflineState() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_TEST_INVITE_SCOPES": "local",
                                 "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        app.buttons["Devices"].firstMatch.tap()
        app.buttons["Add another iPhone or iPad (Show QR)"].tap()

        XCTAssertTrue(app.staticTexts["Entire Account Mesh"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Computers already linked to this iPhone"].exists)
        XCTAssertTrue(app.staticTexts["One computer"].exists)
        XCTAssertTrue(app.staticTexts["One Project Mesh"].exists)
        XCTAssertTrue(app.staticTexts[
            "Sign in with a passkey to show one QR for your whole Account Mesh."].exists)

        app.buttons["Prepare QR for linked computers"].tap()
        XCTAssertTrue(app.staticTexts["Scope Mac is offline and will not be included."].exists)
        XCTAssertFalse(app.buttons["Show linked-computers QR"].isEnabled)
        let computer = app.buttons["Scope Mac"]
        // XCTest can call a clipped List row hittable at the home-indicator edge.
        for _ in 0..<6 where !computer.isHittable || computer.frame.midY > app.frame.maxY - 80 {
            app.swipeUp()
        }
        XCTAssertTrue(computer.isHittable)
        computer.tap()
        let retry = app.buttons["Retry computer"]
        let ready = retry.waitForExistence(timeout: 5)
        let selected = XCTAttachment(screenshot: app.screenshot())
        selected.name = "Selected computer QR actions"
        selected.lifetime = .keepAlways
        add(selected)
        XCTAssertTrue(ready, app.debugDescription)
        XCTAssertFalse(app.buttons["Show this computer QR"].isEnabled)
    }

    func testAccountQRIsSeparateFromComputerAndProjectScopes() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_TEST_INVITE_SCOPES": "account",
                                 "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        app.buttons["Devices"].firstMatch.tap()
        let invite = app.buttons["Add another iPhone or iPad (Show QR)"]
        for _ in 0..<6 where !invite.exists { app.swipeUp() }
        XCTAssertTrue(invite.waitForExistence(timeout: 10))
        invite.tap()

        XCTAssertTrue(app.buttons["Show Account Mesh QR"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["One computer"].exists)
        let projectScope = app.staticTexts["One Project Mesh"]
        for _ in 0..<6 where !projectScope.exists { app.swipeUp() }
        XCTAssertTrue(projectScope.exists)
        for _ in 0..<6 where !app.buttons["Show Account Mesh QR"].exists { app.swipeDown() }
        app.buttons["Show Account Mesh QR"].tap()
        XCTAssertTrue(app.staticTexts[
            "Could not create an Account Mesh QR. Check the account connection and try again."
        ].waitForExistence(timeout: 15))
    }
}
