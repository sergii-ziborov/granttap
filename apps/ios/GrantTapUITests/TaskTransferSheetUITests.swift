import XCTest

final class TaskTransferSheetUITests: XCTestCase {
    func testResumedTaskOffersCheckpointAndFailedSubmissionKeepsTheSheetOpen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_CAPTURE_TAB": "tasks",
            "GRANTTAP_TEST_LANGUAGE": "en", "GRANTTAP_E2E_RESET_ARCHIVE": "1",
            "GRANTTAP_TEST_RESUMED_TRANSFER": "1"]
        app.launch()
        let id = "task:granttap-project-demo\u{001f}granttap-pairing-task-demo"
        let task = app.buttons["task.\(id)"]
        XCTAssertTrue(task.waitForExistence(timeout: 10))
        task.swipeLeft()
        app.buttons["task.send.\(id)"].tap()
        XCTAssertTrue(app.buttons["handoff.close"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["handoff.close"].label, "Cancel")
        let prepare = app.buttons["handoff.submit"]
        XCTAssertTrue(prepare.exists)
        XCTAssertFalse(prepare.isEnabled)
        let reason = app.staticTexts["handoff.blockedReason"]
        XCTAssertTrue(reason.label.contains("uncommitted changes"))
        let checkpoint = app.switches["handoff.checkpoint"]
        let control = checkpoint.switches.firstMatch
        for _ in 0..<4 where !control.isHittable {
            app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(control.isHittable)
        control.tap()
        XCTAssertEqual(control.value as? String, "1")
        capture(app, "Checkpoint selected for resumed chat")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Transfer controls after selecting checkpoint"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: prepare)
        wait(for: [ready], timeout: 5)
        XCTAssertTrue(prepare.isHittable)
        capture(app, "Transfer action remains visible after scrolling")
        prepare.tap()
        let failed = expectation(for: NSPredicate(format: "label == %@", "The handoff was not accepted."),
                                 evaluatedWith: reason)
        wait(for: [failed], timeout: 10)
        XCTAssertTrue(app.buttons["handoff.close"].exists)
        capture(app, "Missing transport is shown without closing the transfer sheet")
        app.buttons["handoff.close"].tap()
        XCTAssertTrue(task.waitForExistence(timeout: 5))
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
