import XCTest

final class PasskeyConnectionUITests: XCTestCase {
    func testAccountMeshIsAvailableWithoutAComputer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()

        let devices = app.buttons["Devices"].firstMatch
        XCTAssertTrue(devices.waitForExistence(timeout: 10))
        devices.tap()
        XCTAssertTrue(app.staticTexts["Account Mesh"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Sign in with passkey"].exists)
        XCTAssertTrue(app.buttons["Add a device (Scan QR)"].exists)
    }

    func testAddingADeviceDoesNotContainAccountSignIn() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()

        let devices = app.buttons["Devices"].firstMatch
        XCTAssertTrue(devices.waitForExistence(timeout: 10))
        devices.tap()
        app.buttons["Add a device (Scan QR)"].tap()
        XCTAssertTrue(app.navigationBars["Add a device"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Scan QR"].exists)
        XCTAssertFalse(app.buttons["Sign in with passkey"].isHittable)
    }
}
