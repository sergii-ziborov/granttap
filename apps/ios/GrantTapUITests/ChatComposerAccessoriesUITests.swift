#if !targetEnvironment(macCatalyst)
import XCTest

final class ChatComposerAccessoriesUITests: XCTestCase {
    func testQueueStartsAsAFloatingControlAndOpensTheRetainedMessages() {
        let app = launch("1", queue: true)
        XCTAssertTrue(app.buttons["chat.queue"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["chat.queue.send.queue-1"].exists,
                       "the retained queue must not take transcript height until opened")
        app.buttons["chat.queue"].tap()
        XCTAssertTrue(app.buttons["chat.queue.send.queue-1"].waitForExistence(timeout: 5))
        capture(app, "Queue message controls")
    }

    func testFilesRemainReachableWithoutRecordedEditsOrAKnownFolder() {
        let app = launch("empty")
        let files = app.buttons["chat.work.files"]
        XCTAssertTrue(files.waitForExistence(timeout: 8))
        XCTAssertEqual(files.label,"Files")
        files.tap()
        XCTAssertTrue(app.segmentedControls["chat.files.mode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls["chat.files.mode"].buttons["All files"].isSelected)
        capture(app, "Files without changes")
    }

    func testWorkspaceLoaderIsCenteredInTheAvailableSheetContent() {
        let app = launch("loading")
        app.buttons["chat.work.files"].tap()
        let loader = app.descendants(matching: .any)
            .matching(identifier: "chat.files.workspace.loading").firstMatch
        XCTAssertTrue(loader.waitForExistence(timeout: 3))
        let picker = app.segmentedControls["chat.files.mode"]
        XCTAssertTrue(picker.exists)
        // Empty SwiftUI accessibility containers can report CGRect.null on iOS 26.
        // Measure the actual space below the visible picker in the app window.
        XCTAssertEqual(loader.frame.midX, app.frame.midX, accuracy: 20)
        let contentCenterY = (picker.frame.maxY + app.frame.maxY) / 2
        XCTAssertEqual(loader.frame.midY, contentCenterY, accuracy: 30)
        capture(app, "Centered workspace loading")
        XCTAssertTrue(app.staticTexts["No files in this folder."].waitForExistence(timeout: 8))
        XCTAssertFalse(loader.exists)
    }

    func testFailedQueueKeepsItsErrorAndAttachmentUntilTheSameMessageIsRetried() {
        let app = launch("1", queue: true, failed: true)
        app.buttons["chat.queue"].tap()
        XCTAssertTrue(app.staticTexts["Delivery was not confirmed after five attempts."].waitForExistence(timeout: 5))
        capture(app, "Failed delivery with retained attachment")
        app.buttons["Preview Queue.txt"].tap()
        XCTAssertTrue(app.textViews["attachment.preview.text"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["attachment.preview.text"].value as? String,"Queued attachment\n")
        app.navigationBars["Queue.txt"].buttons["Done"].tap()
        let retry = app.buttons["chat.queue.send.queue-1"]
        XCTAssertTrue(retry.label.contains("Retry"))
        retry.tap()
        let gone = NSPredicate(format:"exists == false")
        expectation(for:gone,evaluatedWith:app.buttons["chat.queue"])
        waitForExpectations(timeout:5)
        XCTAssertTrue(app.textFields["composer.message"].exists)
    }

    func testJumpButtonLeavesTheFullWidthWorkRailReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_OPEN_SESSION": "1",
            "GRANTTAP_TEST_CHAT_WORK": "1", "GRANTTAP_TEST_LONG_TRANSCRIPT": "1",
            "GRANTTAP_TEST_CHAT_QUEUE": "failed", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        XCTAssertTrue(app.buttons["chat.work.files"].waitForExistence(timeout: 15))
        app.buttons["chat.latest-user-message"].tap()
        let jump = app.buttons["chat.jumpToLatest"]
        XCTAssertTrue(jump.waitForExistence(timeout: 5))
        let rail = app.scrollViews["chat.work.summary"]
        XCTAssertTrue(rail.exists)
        XCTAssertLessThanOrEqual(jump.frame.maxY + 4, rail.frame.minY,
                                "The reading shortcut must sit above the scrolling controls")
        XCTAssertEqual(rail.frame.maxX, app.frame.maxX, accuracy: 3)
        rail.swipeLeft()
        let agents = app.buttons["chat.work.agents"]
        XCTAssertTrue(agents.isHittable)
        agents.tap()
        XCTAssertTrue(app.staticTexts["Agent conversations are nested executions of this Task."]
            .waitForExistence(timeout: 5))
        capture(app, "Accessible full width work rail")
    }

    private func launch(_ scenario: String, queue: Bool = false, failed: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO":"1","GRANTTAP_OPEN_SESSION":"1",
            "GRANTTAP_TEST_CHAT_WORK":scenario,"GRANTTAP_TEST_LANGUAGE":"en"]
        if queue { app.launchEnvironment["GRANTTAP_TEST_CHAT_QUEUE"]=failed ? "failed" : "1" }
        app.launch()
        XCTAssertTrue(app.textFields["composer.message"].waitForExistence(timeout: 15))
        return app
    }

    private func capture(_ app: XCUIApplication,_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name=name
        image.lifetime = .keepAlways
        add(image)
    }
}
#endif
