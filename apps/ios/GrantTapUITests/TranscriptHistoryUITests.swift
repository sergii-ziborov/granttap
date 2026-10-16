import XCTest

final class TranscriptHistoryUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_OPEN_SESSION": "1",
            "GRANTTAP_TEST_TRANSCRIPT_HISTORY": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        XCTAssertTrue(app.buttons["chat.menu"].waitForExistence(timeout: 15))
        let latest = app.buttons["chat.jumpToLatest"]
        if latest.waitForExistence(timeout: 2) { latest.tap() }
        XCTAssertFalse(app.staticTexts["chat.row.history-0"].exists)
        return app
    }

    func testScrollingUpAutomaticallyLoadsEarlierQuestions() {
        continueAfterFailure = false
        let app = launch()
        XCTAssertTrue(app.staticTexts["History review finished"].waitForExistence(timeout: 15))
        let first = app.staticTexts["chat.row.history-0"]
        let transcript = app.descendants(matching: .any)["chat.transcript"].firstMatch
        XCTAssertTrue(transcript.exists)
        for _ in 0..<16 where !first.isHittable {
            transcript.swipeDown()
        }
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.isHittable)
        XCTAssertFalse(app.buttons["chat.history.more"].exists)
        app.buttons["chat.jumpToLatest"].tap()
        XCTAssertTrue(app.buttons["chat.work.files"].waitForExistence(timeout: 5))
    }

    func testChangedFilesExpandAndOpenDiff() {
        continueAfterFailure = false
        let app = launch()
        let review = app.buttons["chat.work.files"]
        XCTAssertTrue(review.waitForExistence(timeout: 15))
        for _ in 0..<8 where !review.isHittable { app.swipeUp() }
        review.tap()
        let file = app.buttons["chat.files.modified./demo/file-7.swift"]
        for _ in 0..<8 where !file.isHittable { app.swipeUp() }
        XCTAssertTrue(file.isHittable)
        file.tap()
        let short = app.staticTexts["+new value 7"]
        XCTAssertTrue(short.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["chat.review.path"].exists)
        XCTAssertTrue(app.staticTexts["This diff exceeds the preview limit."].exists)
        let initialX = short.frame.minX
        let scroll = app.scrollViews["chat.review.scroll"]
        let long = app.staticTexts.matching(NSPredicate(
            format: "label == %@", "+BEGIN " + String(repeating: "source ", count: 30) + " END"
        )).firstMatch
        XCTAssertTrue(scroll.exists)
        XCTAssertGreaterThan(long.frame.width, scroll.frame.width)
        for _ in 0..<10 where long.frame.maxX > scroll.frame.maxX { scroll.swipeLeft() }
        XCTAssertLessThanOrEqual(long.frame.maxX, scroll.frame.maxX + 2)
        XCTAssertLessThan(short.frame.minX, initialX - 100)
        scroll.swipeRight()
        app.navigationBars["file-7.swift"].buttons["Done"].tap()
        XCTAssertTrue(file.waitForExistence(timeout: 5))
        file.tap()
        XCTAssertTrue(short.waitForExistence(timeout: 5))
        XCTAssertEqual(short.frame.minX, initialX, accuracy: 2, "Reopening must restore the start of the file.")
        app.navigationBars["file-7.swift"].buttons["Done"].tap()
    }

    func testCommandDetailsShowResourcesAndQualifyTokenAndCpuEstimates() {
        continueAfterFailure = false
        let app = launch()
        let run = app.buttons["chat.run.run:history-command"]
        XCTAssertTrue(run.waitForExistence(timeout: 15))
        for _ in 0..<8 where !run.isHittable { app.swipeDown() }
        run.tap()
        let step = app.buttons["run.step.history-command"]
        XCTAssertTrue(step.waitForExistence(timeout: 5))
        step.tap()
        let cpu = app.staticTexts["~75.0%"]
        for _ in 0..<6 where !cpu.isHittable { app.swipeUp() }
        XCTAssertTrue(cpu.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["~7.5s"].exists)
        XCTAssertTrue(app.staticTexts["~286 MB"].exists)
        XCTAssertTrue(app.staticTexts["Estimated context tokens"].exists)
        XCTAssertTrue(app.staticTexts["~320 tok"].exists)
        XCTAssertTrue(app.staticTexts["Approximate share of agent processes"].exists)
    }
}


extension TranscriptHistoryUITests {
    func testPinnedRequestFollowsManualUpwardReadingAndSkipsAttachmentFragments() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_OPEN_SESSION": "1",
            "GRANTTAP_TEST_TRANSCRIPT_HISTORY": "1", "GRANTTAP_TEST_PINNED_SCROLL": "1",
            "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let previous = app.buttons["chat.latest-user-message"]
        let navigationAvailable = previous.waitForExistence(timeout: 30)
        if !navigationAvailable {
            let evidence = XCTAttachment(screenshot: app.screenshot())
            evidence.lifetime = .keepAlways
            add(evidence)
        }
        XCTAssertTrue(navigationAvailable)
        let startsAtSecond = waitForLabel(previous, contains: "Second viewport request", timeout: 2)
        XCTAssertTrue(startsAtSecond || waitForLabel(previous, contains: "Third viewport request"))
        previous.tap()
        if !startsAtSecond {
            XCTAssertTrue(waitForLabel(previous, contains: "Second viewport request"))
            previous.tap()
        }
        XCTAssertTrue(waitForLabel(previous, contains: "First viewport request"))
        let transcript = app.descendants(matching: .any)["chat.transcript"].firstMatch
        let second = app.staticTexts["chat.row.viewport-request-1"]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        let latest = app.buttons["chat.jumpToLatest"]
        XCTAssertTrue(latest.isHittable)
        XCTAssertGreaterThan(latest.frame.midY, transcript.frame.minY + transcript.frame.height * 0.6,
            "Jump to latest should float near the bottom of the transcript.")
        XCTAssertLessThanOrEqual(second.frame.minY, transcript.frame.minY + 30,
            "The pinned request must scroll to its message, not only change its title.")
        for _ in 0..<16 where !previous.label.contains("First viewport request") { transcript.swipeDown() }
        XCTAssertTrue(waitForLabel(previous, contains: "First viewport request"))
        let first = app.staticTexts["chat.row.viewport-request-0"]
        XCTAssertFalse(first.isHittable, "The earlier request must remain outside the reading position.")
        previous.tap()
        XCTAssertTrue(waitForHittable(first), "The previous request must be brought into view.")
        XCTAssertLessThanOrEqual(first.frame.minY, transcript.frame.minY + 30,
            "The previous request must land at the top of the transcript.")
        XCTAssertTrue(previous.label.contains("First viewport request"))
    }

    func testPreviousRequestNavigationPreloadsAndAdvancesWithoutManualPaging() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_OPEN_SESSION": "1",
            "GRANTTAP_TEST_TRANSCRIPT_HISTORY": "1", "GRANTTAP_TEST_REQUEST_NAVIGATION": "1",
            "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let previous = app.buttons["chat.latest-user-message"]
        let navigationAvailable = previous.waitForExistence(timeout: 15)
        if !navigationAvailable {
            let evidence = XCTAttachment(screenshot: app.screenshot())
            evidence.lifetime = .keepAlways
            add(evidence)
        }
        XCTAssertTrue(navigationAvailable)
        // The newest loaded request may already be visible on a short screen.
        // The control then points directly to the next request above it.
        let startsAtLatest = waitForLabel(previous, contains: "Latest user request", timeout: 2)
        XCTAssertTrue(startsAtLatest || waitForLabel(previous, contains: "Previous user request"))
        XCTAssertTrue(app.buttons["chat.project"].exists)
        XCTAssertTrue(app.staticTexts["chat.time.history-final"].exists)
        if startsAtLatest {
            previous.tap()
            XCTAssertTrue(app.staticTexts["chat.row.request-0"].isHittable)
            XCTAssertTrue(app.staticTexts["chat.time.request-0"].exists)
            XCTAssertTrue(waitForLabel(previous, contains: "Previous user request"))
        }
        previous.tap()
        XCTAssertTrue(app.staticTexts["chat.row.request-1"].isHittable)
        XCTAssertTrue(waitForLabel(previous, contains: "First user request"))
        XCTAssertFalse(app.buttons["chat.history.more"].exists)
        previous.tap()
        XCTAssertTrue(app.staticTexts["chat.row.request-2"].isHittable)
        XCTAssertTrue(waitForLabel(previous, contains: "First user request"))
    }

    private func waitForLabel(_ element: XCUIElement, contains text: String,
                              timeout: TimeInterval = 10) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)],
            timeout: timeout) == .completed
    }

    private func waitForHittable(_ element: XCUIElement) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: element)], timeout: 5) == .completed
    }
}
