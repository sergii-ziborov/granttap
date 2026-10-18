import XCTest

final class NotificationNavigationUITests: XCTestCase {
    func testNotificationOpensItsCursorRequestFromTasksAndWaitsForEncryptedPayload() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_CAPTURE_TAB": "tasks",
            "GRANTTAP_TEST_NOTIFICATION_OPEN": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Cursor notification approval fixture"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["approval.allow.cursor-notification-fixture"].exists
            || app.buttons.matching(NSPredicate(format: "label == 'Allow'")).firstMatch.exists)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Notification opens the exact Cursor request"; capture.lifetime = .keepAlways
        add(capture)
    }
}
