import XCTest

final class ApprovalDetailsUITests: XCTestCase {
    func testCardOpensDetailsWithoutDecidingAndShowsChatAutomation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        #if targetEnvironment(simulator)
        let storePrompt = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            .alerts["Sign in to Apple Account"]
        if storePrompt.exists { storePrompt.buttons["Cancel"].tap() }
        #endif
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let body = app.buttons["approval.details.demo-approval"]
        XCTAssertTrue(body.waitForExistence(timeout: 10))
        body.tap()
        XCTAssertTrue(app.staticTexts["approval.detail.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["approval.detail.command"].exists)
        XCTAssertTrue(app.buttons["approval.open-chat.demo-approval"].exists)
        XCTAssertTrue(app.switches["approval.auto-safe.demo-approval"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Approval details and automation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(body.waitForExistence(timeout: 5), "Inspecting the card must not decide it.")
        XCTAssertTrue(app.buttons["Allow"].exists)
        XCTAssertTrue(app.buttons["Deny"].exists)
    }
}
