import XCTest

final class DeviceNameUITests: XCTestCase {
    func testDevicesRejectsLongNameAndClearsErrorAfterSave() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        app.buttons["Devices"].firstMatch.tap()

        let name = app.textFields["devices.controller-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        let previous = name.value as? String ?? ""
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        name.typeText(String(repeating: "x", count: 81))
        app.buttons["devices.save-controller-name"].tap()

        let error = app.staticTexts["devices.controller-name-error"]
        XCTAssertTrue(error.exists)
        XCTAssertEqual(error.label, "Use a name of up to 80 characters.")

        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 81))
        name.typeText("QA iPhone")
        app.buttons["devices.save-controller-name"].tap()
        XCTAssertFalse(error.exists)
        XCTAssertEqual(name.value as? String, "QA iPhone")
    }

    func testDevicesSavesAnEditableControllerName() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        app.buttons["Devices"].firstMatch.tap()

        let name = app.textFields["devices.controller-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        let previous = name.value as? String ?? ""
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        name.typeText("QA iPhone")
        app.buttons["devices.save-controller-name"].tap()

        XCTAssertEqual(name.value as? String, "QA iPhone")
        XCTAssertFalse(app.staticTexts["Use a name of up to 80 characters."].exists)
    }
}
