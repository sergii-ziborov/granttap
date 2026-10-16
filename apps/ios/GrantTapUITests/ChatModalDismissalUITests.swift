import XCTest

final class ChatModalDismissalUITests: XCTestCase {
    func testDoneClosesChatSheetsAndTheyCanBeOpenedAgain() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_OPEN_SESSION": "1",
            "GRANTTAP_TEST_CHAT_WORK": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.buttons["chat.work.agents"].waitForExistence(timeout: 15))
        for _ in 0..<2 {
            press(app.buttons["chat.work.agents"])
            close("chat.agents.done", in: app)
            press(app.buttons["chat.work.files"])
            close("chat.files.done", in: app)
            press(app.buttons["chat.menu"])
            #if targetEnvironment(macCatalyst)
            press(app.menuItems["Task controls"])
            #else
            press(app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@",
                "Task controls", "chat.menu")).firstMatch)
            #endif
            close("chat.controls.done", in: app)
        }
    }

    private func close(_ identifier: String, in app: XCUIApplication) {
        let done = app.buttons[identifier]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(done.isEnabled)
        press(done)
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: done)
        wait(for: [closed], timeout: 5)
        XCTAssertTrue(app.buttons["chat.work.agents"].waitForExistence(timeout: 5))
    }

    private func press(_ element: XCUIElement) {
        #if targetEnvironment(macCatalyst)
        element.click()
        #else
        element.tap()
        #endif
    }
}
