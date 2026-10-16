import XCTest

final class ChatFileEditingUITests: XCTestCase {
    func testPreviewEditsAreReviewedAndQueuedThenDoneClosesTheFileOnBothPlatforms() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_OPEN_SESSION": "1",
            "GRANTTAP_TEST_CHAT_WORK": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        #if targetEnvironment(macCatalyst)
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO"]
        #endif
        app.launch()
        app.activate()
        #if targetEnvironment(macCatalyst)
        if !app.buttons["chat.work.files"].waitForExistence(timeout: 5) {
            press(app.buttons["sidebar.tasks"])
            let chat = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "GrantTap release audit")).firstMatch
            XCTAssertTrue(chat.waitForExistence(timeout: 15))
            press(chat)
        }
        #endif
        let files = app.buttons["chat.work.files"]
        XCTAssertTrue(files.waitForExistence(timeout: 15))
        press(files)
        let mode = app.segmentedControls["chat.files.mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        press(mode.buttons["All files"])
        press(app.buttons["chat.files.workspace.README.md"])
        let preview = app.staticTexts["chat.files.preview.text"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(preview.label.contains("Fixture file"))
        press(app.buttons["chat.files.preview.edit"])
        let editor = app.textViews["chat.file-edit.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        press(editor)
        editor.typeText("\nRequested from the preview.\n")
        XCTAssertTrue((editor.value as? String)?.contains("Requested from the preview.") == true)
        let ready = expectation(for: NSPredicate(format: "enabled == true"),
            evaluatedWith: app.buttons["chat.file-edit.review"])
        wait(for: [ready], timeout: 5)
        press(app.buttons["chat.file-edit.done"])
        capture(app, "Unsent file edit confirmation")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Unsent file edit confirmation accessibility"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        #if targetEnvironment(macCatalyst)
        let keep = app.sheets.matching(NSPredicate(format: "label == %@", "alert"))
            .buttons["Keep editing"].firstMatch
        #else
        let keep = app.buttons["Keep editing"].firstMatch
        #endif
        XCTAssertTrue(keep.waitForExistence(timeout: 5))
        press(keep)
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        press(app.buttons["chat.file-edit.review"])
        let send = app.buttons["chat.file-edit.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        capture(app, "Review proposed file edits")
        press(send)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "chat.file-edit.status")
            .firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["chat.file-edit.send"].exists, "The same request cannot be sent twice.")
        capture(app, "Queued file edit request")
        press(app.buttons["chat.file-edit.done"])
        XCTAssertTrue(app.buttons["chat.files.preview.done"].waitForExistence(timeout: 5))
        press(app.buttons["chat.files.preview.done"])
        XCTAssertTrue(app.buttons["chat.files.workspace.README.md"].waitForExistence(timeout: 5))
        press(app.buttons["chat.files.done"])
        XCTAssertTrue(files.waitForExistence(timeout: 5))
        app.terminate()
    }

    private func press(_ element: XCUIElement) {
        #if targetEnvironment(macCatalyst)
        element.click()
        #else
        element.tap()
        #endif
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
