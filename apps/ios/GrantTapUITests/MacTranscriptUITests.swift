#if targetEnvironment(macCatalyst)
import XCTest

final class MacTranscriptUITests: XCTestCase {
    func testMouseWheelLoadsEarlierHistoryAndCanReturnToTheLatestReply() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_TEST_LANGUAGE": "en",
            "GRANTTAP_OPEN_SESSION": "1", "GRANTTAP_TEST_TRANSCRIPT_HISTORY": "1"]
        app.launch()
        app.activate()
        if !app.textViews["composer.message"].waitForExistence(timeout: 5) {
            app.buttons["sidebar.tasks"].click()
            let task = app.buttons["task.task:granttap-project-demo\u{1f}granttap-release-task-demo"]
            XCTAssertTrue(task.waitForExistence(timeout: 10))
            task.click()
        }
        XCTAssertTrue(app.staticTexts["History review finished"].waitForExistence(timeout: 10))
        let first = app.staticTexts["chat.row.history-0"]
        XCTAssertFalse(first.exists)
        let transcript = app.collectionViews["chat.transcript"]
        capture(app, name: "History before wheel navigation")
        for _ in 0..<16 where !first.isHittable {
            transcript.scroll(byDeltaX: 0, deltaY: 600)
        }
        capture(app, name: "Earlier transcript after navigation")
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.isHittable, "Mouse-wheel reading must advance native history pages.")
        let jump = app.buttons["chat.jumpToLatest"]
        XCTAssertTrue(jump.waitForExistence(timeout: 5))
        jump.click()
        XCTAssertTrue(app.staticTexts["History review finished"].isHittable)
        app.terminate()
    }

    func testLongChatRecyclesRowsAndRemainsNavigableWithTheMouse() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_TEST_LANGUAGE": "en",
            "GRANTTAP_OPEN_SESSION": "1", "GRANTTAP_TEST_LONG_TRANSCRIPT": "1"]
        app.launch()
        app.activate()
        let composer = app.textViews["composer.message"]
        if !composer.waitForExistence(timeout: 5) {
            app.buttons["sidebar.tasks"].click()
            let task = app.buttons["task.task:granttap-project-demo\u{1f}granttap-release-task-demo"]
            XCTAssertTrue(task.waitForExistence(timeout: 10))
            task.click()
        }
        let last = app.staticTexts["chat.row.long-4999"]
        XCTAssertTrue(last.waitForExistence(timeout: 15))
        XCTAssertTrue(last.isHittable)
        let visibleRows = app.staticTexts.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "chat.row.long-"))
        XCTAssertLessThan(visibleRows.count, 100,
                         "Opening a long Mac chat must not render the whole archive.")
        let previous = app.buttons["chat.latest-user-message"]
        previous.click()
        let first = app.staticTexts["chat.row.long-0"]
        let transcript = app.collectionViews["chat.transcript"]
        if !first.exists || !transcript.frame.intersects(first.frame) { previous.click() }
        capture(app, name: "Earlier transcript after navigation")
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(transcript.frame.intersects(first.frame), "The oldest saved row must be visible.")
        transcript.scroll(byDeltaX: 0, deltaY: -500)
        transcript.scroll(byDeltaX: 0, deltaY: 500)
        let jump = app.buttons["chat.jumpToLatest"]
        XCTAssertTrue(jump.waitForExistence(timeout: 5))
        jump.click()
        XCTAssertTrue(last.isHittable)
        let hidden = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: jump)
        wait(for: [hidden], timeout: 5)
        app.activate()
        XCTAssertEqual(app.state, .runningForeground)
        let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        image.name = "Mac long chat after scrolling"
        image.lifetime = .keepAlways
        add(image)
        app.terminate()
    }
    private func capture(_ app: XCUIApplication, name: String) {
        let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + " accessibility"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

}
#endif
