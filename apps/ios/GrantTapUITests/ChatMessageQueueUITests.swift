import XCTest

final class ChatMessageQueueUITests: XCTestCase {
    func testPinnedQueueCanAddPreviewSendNowAndCancelWithoutScrollingAway() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_OPEN_SESSION": "1",
            "GRANTTAP_TEST_CHAT_QUEUE": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let first = app.buttons["chat.queue.send.queue-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        let firstY = first.frame.midY
        app.scrollViews.firstMatch.swipeDown()
        XCTAssertEqual(first.frame.midY, firstY, accuracy: 1)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Pinned follow-up queue above composer"
        image.lifetime = .keepAlways
        add(image)

        app.buttons["Preview Queue.txt"].tap()
        let text = app.textViews["attachment.preview.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertEqual(text.value as? String, "Queued attachment\n")
        app.buttons["Done"].tap()

        app.buttons["chat.queue.cancel.queue-2"].tap()
        XCTAssertFalse(app.staticTexts["Queued follow-up 2"].exists)
        XCTAssertTrue(app.staticTexts["Queued follow-up 1"].exists)
        XCTAssertTrue(app.staticTexts["Queued follow-up 3"].exists)
        app.buttons["composer.queue"].tap()
        app.buttons["composer.queue.add"].tap()
        XCTAssertTrue(app.staticTexts["Next queued message"].waitForExistence(timeout: 5))

        first.tap()
        XCTAssertFalse(app.buttons["chat.queue.send.queue-1"].exists)
        XCTAssertTrue(app.staticTexts["Queued follow-up 3"].exists)
        XCTAssertTrue(app.staticTexts["Next queued message"].exists)
        XCTAssertTrue(app.buttons["chat.attachment.local-user-queue-1.Queue.txt"].exists)
        app.buttons["chat.queue"].tap()
        XCTAssertFalse(app.buttons["chat.queue.send.queue-3"].exists)
        app.buttons["chat.queue"].tap()
        XCTAssertTrue(app.buttons["chat.queue.send.queue-3"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chat.queue.send.queue-3"].isHittable)
    }
}
