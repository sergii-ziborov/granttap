import XCTest

final class MarkdownPasteUITests: XCTestCase {
    func testPastedMarkdownInAQuestionReplyRemainsTextAndCanBeSubmitted() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_OPEN_SESSION": "1",
            "GRANTTAP_TEST_MARKDOWN_PASTE": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let reply = app.buttons["Reply"].firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 15))
        reply.tap()
        let editor = app.textViews["composer.message"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.press(forDuration: 1.1)
        let paste = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Paste")).firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        paste.tap()
        let typed = NSPredicate(format: "value CONTAINS %@", "Review checklist")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: typed, object: editor)], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["attachment.preview.Pasted.md"].exists)
        app.buttons["composer.send"].tap()
        XCTAssertFalse((editor.value as? String ?? "").contains("Review checklist"))
        XCTAssertFalse(reply.exists)
    }

    func testOrdinaryPasteStaysTextAndTheKeyboardSendQueuesIt() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_OPEN_SESSION": "1",
            "GRANTTAP_TEST_MARKDOWN_PASTE": "plain", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let editor = app.textViews["composer.message"]
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        editor.tap()
        editor.press(forDuration: 1.1)
        let paste = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Paste")).firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        paste.tap()
        let typed = NSPredicate(format: "value CONTAINS %@", "Continue with the tests.")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: typed, object: editor)], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["attachment.preview.Pasted.md"].exists)
        let send = app.keyboards.buttons["Send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()
        XCTAssertTrue(app.buttons["chat.queue"].waitForExistence(timeout: 5))
        XCTAssertFalse((editor.value as? String ?? "").contains("Continue with the tests."))
    }

    func testSystemPasteCreatesAPreviewableMarkdownAttachmentWithoutFillingTheComposer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_OPEN_SESSION": "1",
            "GRANTTAP_TEST_MARKDOWN_PASTE": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let editor = app.textViews["composer.message"]
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        editor.tap()
        editor.press(forDuration: 1.1)
        let paste = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Paste")).firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        paste.tap()
        let attachment = app.buttons["attachment.preview.Pasted.md"]
        XCTAssertTrue(attachment.waitForExistence(timeout: 5))
        XCTAssertFalse((editor.value as? String ?? "").contains("Review checklist"))
        attachment.tap()
        let preview = app.textViews["attachment.preview.text"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue((preview.value as? String ?? "").contains("let ready = true"))
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Pasted Markdown file preview"
        image.lifetime = .keepAlways
        add(image)
        app.buttons["Done"].tap()
        app.buttons["Remove Pasted.md"].tap()
        XCTAssertFalse(attachment.exists)
    }
}
