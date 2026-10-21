import XCTest

#if !targetEnvironment(macCatalyst)
final class ChatStopControlUITests: XCTestCase {
    func testRunningTaskHasAVisibleStopWithoutOpeningItsMenu() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_OPEN_SESSION": "1",
                                 "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let stop = app.buttons["composer.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        XCTAssertTrue(stop.isHittable)
        XCTAssertEqual(stop.label, "Stop task")
        XCTAssertEqual(stop.value as? String, "Working")
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Working task stop control"
        image.lifetime = .keepAlways
        add(image)
        let composer = app.textFields["composer.message"]
        composer.tap()
        composer.typeText("Queued follow-up")
        XCTAssertTrue(stop.isHittable, "Writing a follow-up must not hide control of the running task.")
        XCTAssertTrue(app.buttons["composer.send"].isEnabled)
    }
}
#endif
