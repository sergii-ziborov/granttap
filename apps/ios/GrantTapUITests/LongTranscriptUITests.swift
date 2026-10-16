import XCTest

#if !targetEnvironment(macCatalyst)
final class LongTranscriptUITests: XCTestCase {
    func testFiveThousandSavedMessagesRemainNavigableAndComposerResponds() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_OPEN_SESSION": "1",
                                 "GRANTTAP_TEST_LONG_TRANSCRIPT": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let last = app.staticTexts["chat.row.long-4999"]
        XCTAssertTrue(last.waitForExistence(timeout: 15))
        XCTAssertTrue(last.isHittable)
        XCTAssertLessThan(app.staticTexts.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "chat.row.long-")).count, 100,
            "The actual chat must expose only visible/prefetched message rows.")
        let previous = app.buttons["chat.latest-user-message"]
        previous.tap()
        let first = app.staticTexts["chat.row.long-0"]
        if !first.isHittable { previous.tap() }
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.isHittable, "Oldest locally saved message must still be reachable.")
        let transcript = app.descendants(matching: .any)["chat.transcript"].firstMatch
        transcript.swipeUp()
        transcript.swipeDown()
        app.buttons["chat.jumpToLatest"].tap()
        XCTAssertTrue(last.waitForExistence(timeout: 5))
        XCTAssertTrue(last.isHittable)
        let jump = app.buttons["chat.jumpToLatest"]
        let hidden = NSPredicate(format: "exists == false")
        expectation(for: hidden, evaluatedWith: jump)
        waitForExpectations(timeout: 5)
        let composer = app.textFields["composer.message"]
        XCTAssertTrue(composer.isHittable)
        composer.tap()
        composer.typeText("Responsive after a long transcript")
        XCTAssertTrue(app.buttons["composer.send"].isEnabled)
        XCTAssertTrue(composer.value as? String == "Responsive after a long transcript")
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Five thousand locally saved messages"
        image.lifetime = .keepAlways
        add(image)
    }
}
#endif
