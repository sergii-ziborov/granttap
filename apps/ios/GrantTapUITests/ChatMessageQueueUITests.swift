import XCTest

final class ChatMessageQueueUITests: XCTestCase {
    func testSendNowOnSavedRelayJobShowsCancellationProgress() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_OPEN_SESSION": "1",
            "GRANTTAP_TEST_CHAT_QUEUE": "relay", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        XCTAssertTrue(app.buttons["chat.queue"].waitForExistence(timeout: 15))
        app.buttons["chat.queue"].tap()
        XCTAssertTrue(app.staticTexts["Saved on relay"].waitForExistence(timeout: 5))
        app.buttons["chat.queue.send.queue-1"].tap()
        XCTAssertTrue(app.staticTexts["Waiting for relay cancellation"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["chat.queue.send.queue-1"].isEnabled)
        capture(app, "Send now confirms relay cancellation")
    }

    func testFloatingQueueCanPreviewSendNowAndCancelWithoutOccupyingTranscript() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_OPEN_SESSION": "1",
            "GRANTTAP_TEST_CHAT_QUEUE": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let queue = app.buttons["chat.queue"]
        XCTAssertTrue(queue.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["chat.queue.send.queue-1"].exists)
        let transcript = app.descendants(matching: .any).matching(identifier: "chat.transcript").firstMatch
        let height = transcript.frame.height
        capture(app, "Floating queue and work controls")
        queue.tap()
        let first = app.buttons["chat.queue.send.queue-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        app.buttons["Preview Queue.txt"].tap()
        let text = app.textViews["attachment.preview.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertEqual(text.value as? String, "Queued attachment\n")
        app.navigationBars["Queue.txt"].buttons["Done"].tap()
        app.buttons["chat.queue.cancel.queue-2"].tap()
        XCTAssertFalse(app.staticTexts["Queued follow-up 2"].exists)
        XCTAssertTrue(app.staticTexts["Queued follow-up 3"].exists)
        first.tap()
        XCTAssertFalse(first.exists)
        app.buttons["chat.queue.done"].tap()
        XCTAssertEqual(transcript.frame.height,height,accuracy: 1)
        XCTAssertTrue(app.buttons["chat.attachment.local-user-queue-1.Queue.txt"].exists)
        app.buttons["composer.queue"].tap()
        app.buttons["composer.queue.add"].tap()
        queue.tap()
        XCTAssertTrue(app.staticTexts["Next queued message"].waitForExistence(timeout: 5))
        capture(app, "Retained queue messages and actions")
        app.buttons["chat.queue.done"].tap()
        XCTAssertEqual(transcript.frame.height,height,accuracy: 1)
    }

    private func capture(_ app: XCUIApplication,_ name: String) {
        let image=XCTAttachment(screenshot:app.screenshot())
        image.name=name
        image.lifetime = .keepAlways
        add(image)
    }
}
