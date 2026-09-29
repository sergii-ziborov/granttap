import UIKit
import XCTest

final class ProjectControllerDeviceUITests: XCTestCase {
    func testMembersNamesTheCurrentDevice() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "GRANTTAP_DEMO": "1", "GRANTTAP_CAPTURE_TAB": "projects",
            "GRANTTAP_TEST_LANGUAGE": "en",
        ]
        app.launch()
        let project = app.buttons["projects.row.granttap-project-demo"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let members = app.buttons["project.members"]
        for _ in 0..<5 where !members.exists { app.swipeUp() }
        XCTAssertTrue(members.waitForExistence(timeout: 10))
        members.tap()
        let device = app.staticTexts["members.controller-device"]
        XCTAssertTrue(device.waitForExistence(timeout: 10))
        #if targetEnvironment(macCatalyst)
        XCTAssertEqual(device.label, "This Mac")
        #else
        XCTAssertEqual(device.label, UIDevice.current.userInterfaceIdiom == .pad ? "This iPad" : "This iPhone")
        #endif
    }
}
