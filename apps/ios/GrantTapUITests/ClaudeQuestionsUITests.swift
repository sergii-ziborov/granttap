import XCTest

final class ClaudeQuestionsUITests: XCTestCase {
    func testNativeQuestionsSupportChoiceMultipleSelectionsAndOtherWithoutAutoAllow() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_TEST_LANGUAGE": "en",
                                 "GRANTTAP_TEST_CLAUDE_QUESTIONS": "1"]
        app.launch()
        let card = app.buttons["approval.details.demo-claude-question"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        let first = app.buttons["approval.question.option.0.0"]
        reveal(first, in: app)
        first.tap()
        XCTAssertTrue(first.isSelected)
        let other = app.buttons["approval.question.other.0"]
        reveal(other, in: app)
        other.tap()
        let field = app.textFields["approval.question.other-text.0"].firstMatch
        let multiline = app.textViews["approval.question.other-text.0"].firstMatch
        let input = field.exists ? field : multiline
        reveal(input, in: app)
        input.tap()
        input.typeText("My distribution")
        let finishTyping = app.buttons["approval.question.keyboard-done"]
        XCTAssertTrue(finishTyping.waitForExistence(timeout: 5))
        finishTyping.tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.swipeUp()
        for option in 0...1 {
            let choice = app.buttons["approval.question.option.1.\(option)"]
            reveal(choice, in: app)
            choice.tap()
            XCTAssertTrue(choice.isSelected)
        }
        XCTAssertFalse(app.switches["approval.auto-safe.demo-claude-question"].exists)
        let submit = app.buttons["approval.question.submit"]
        reveal(submit, in: app)
        XCTAssertTrue(submit.exists)
        XCTAssertFalse(submit.isEnabled, "Demo cannot send answers to a real provider")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Claude question choices and Other"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
}
