import XCTest

final class MessageImageUITests: XCTestCase {
    func testGeneratedImagesShowPreviewsAndOpenFullScreen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_TEST_ARTIFACT_IMAGES": "1",
                                 "GRANTTAP_OPEN_SESSION": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let last = app.buttons["chat.image.demo-artifact-15"]
        XCTAssertTrue(last.waitForExistence(timeout: 15))
        for _ in 0..<8 where !last.isHittable { app.swipeUp() }
        XCTAssertTrue(last.isEnabled, "the last generated PNG has decoded bytes")
        let first = app.buttons["chat.image.demo-artifact-1"]
        for _ in 0..<12 where !first.isHittable { app.swipeDown() }
        XCTAssertTrue(first.exists)
        XCTAssertTrue(first.isEnabled, "the first PNG is a picture, not a disabled filename")
        add(XCTAttachment(screenshot: app.screenshot()))
        first.tap()
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        add(XCTAttachment(screenshot: app.screenshot()))
        close.tap()
        XCTAssertTrue(first.waitForExistence(timeout: 10))
    }
}
