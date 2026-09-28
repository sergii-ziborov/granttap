import XCTest

final class AttachmentPreviewUITests: XCTestCase {
    func testAttachmentsStayInOneHorizontalRowAndScrollToTheLastFile() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_OPEN_SESSION": "1",
            "GRANTTAP_TEST_ATTACHMENT_FILES": "1", "GRANTTAP_TEST_ATTACHMENT_SCROLL": "1",
            "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let first = app.buttons["chat.attachment.local-user-demo-photo-delivery.Fixture.swift"]
        let second = app.buttons["chat.attachment.local-user-demo-photo-delivery.Fixture.pdf"]
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        capture(app, name: "Ten sent attachments and draft attachments")
        XCTAssertEqual(first.frame.midY, second.frame.midY, accuracy: 1)
        XCTAssertGreaterThan(second.frame.minX, first.frame.maxX)
        let sentStrip = app.scrollViews["chat.row.local-user-demo-photo-delivery"]
        let last = app.buttons["chat.attachment.local-user-demo-photo-delivery.File-10.txt"]
        XCTAssertFalse(last.isHittable)
        for _ in 0..<10 where !last.isHittable { sentStrip.swipeLeft() }
        XCTAssertTrue(last.isHittable)
        last.tap()
        let text = app.textViews["attachment.preview.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertEqual(text.value as? String, "Attachment 10\n")
        app.buttons["Done"].tap()
        let draftFirst = app.buttons["attachment.preview.Fixture.swift"]
        let draftSecond = app.buttons["attachment.preview.Fixture.pdf"]
        XCTAssertEqual(draftFirst.frame.midY, draftSecond.frame.midY, accuracy: 1)
        XCTAssertGreaterThan(draftSecond.frame.minX, draftFirst.frame.maxX)
        let draftLast = app.buttons["attachment.preview.File-10.txt"]
        let draftStrip = app.scrollViews["composer.attachments"]
        XCTAssertFalse(draftLast.isHittable)
        for _ in 0..<4 where !draftLast.isHittable { draftStrip.swipeLeft() }
        XCTAssertTrue(draftLast.isHittable)
        draftLast.tap()
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertEqual(text.value as? String, "Attachment 10\n")
        capture(app, name: "Last file preview after horizontal scrolling")
    }

    func testSourceAndPDFDraftsCanBePreviewedAndRemovedIndependently() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_OPEN_SESSION": "1",
            "GRANTTAP_TEST_ATTACHMENT_FILES": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let source = app.buttons["attachment.preview.Fixture.swift"]
        XCTAssertTrue(source.waitForExistence(timeout: 15))
        source.tap()
        let text = app.textViews["attachment.preview.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 8))
        XCTAssertTrue((text.value as? String)?.contains("let attachmentPreview = 42") == true)
        capture(app, name: "Source attachment preview")
        app.buttons["Done"].tap()
        app.buttons["attachment.preview.Fixture.pdf"].tap()
        let closePDF = app.buttons["QLOverlayDoneButtonAccessibilityIdentifier"]
        XCTAssertTrue(closePDF.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["PDF attachment fixture"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.textViews["attachment.preview.text"].exists)
        capture(app, name: "PDF attachment preview")
        closePDF.tap()
        app.buttons["Remove Fixture.swift"].tap()
        XCTAssertFalse(source.exists)
        XCTAssertTrue(app.buttons["attachment.preview.Fixture.pdf"].exists)
        capture(app, name: "Flat composer and remaining file")
        app.buttons["Add to this message"].tap()
        XCTAssertTrue(app.buttons["Choose Files"].waitForExistence(timeout: 5))
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
