import XCTest

final class ComposerApprovalUITests: XCTestCase {
    func testComposerOpensDescribedApprovalChoicesAndDoneClosesOnBothClients() {
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
        if !app.buttons["composer.approval"].waitForExistence(timeout: 5) {
            press(app.buttons["sidebar.tasks"])
            let chat = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "GrantTap release audit")).firstMatch
            XCTAssertTrue(chat.waitForExistence(timeout: 15))
            press(chat)
        }
        #endif
        let shortcut = app.buttons["composer.approval"]
        XCTAssertTrue(shortcut.waitForExistence(timeout: 15))
        press(shortcut)
        let ask = app.buttons["chat.approval.select.every"]
        XCTAssertTrue(ask.waitForExistence(timeout: 5))
        XCTAssertTrue(ask.label.contains("Ask before every action"))
        XCTAssertTrue(app.buttons["chat.approval.select.risky"].label.contains("external writes"))
        XCTAssertTrue(app.buttons["chat.approval.select.full"].label.contains("Global and Mesh blocks"))
        XCTAssertTrue(app.buttons["chat.approval.select.defaults"].label.contains("provider's own"))
        XCTAssertFalse(ask.isEnabled, "Demo must never change a real approval rule.")
        capture(app, "Direct chat approval choices")
        press(app.buttons["chat.approval.done"])
        XCTAssertTrue(shortcut.waitForExistence(timeout: 5))
        XCTAssertFalse(ask.exists)
        #if targetEnvironment(macCatalyst)
        let field = app.textViews["composer.message"]
        #else
        let field = app.textViews["composer.message"]
        #endif
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        press(field)
        field.typeText("Draft with approval controls")
        XCTAssertTrue(shortcut.isHittable)
        XCTAssertTrue(app.buttons["composer.model"].isHittable)
        XCTAssertTrue(app.buttons["composer.stop"].isHittable)
        XCTAssertTrue(app.buttons["composer.send"].isHittable)
        capture(app, "Composer approval shortcut with a draft")
        press(shortcut)
        XCTAssertTrue(ask.waitForExistence(timeout: 5))
        press(app.buttons["chat.approval.done"])
        XCTAssertTrue(shortcut.waitForExistence(timeout: 5))
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
        let item = XCTAttachment(screenshot: app.screenshot())
        item.name = name
        item.lifetime = .keepAlways
        add(item)
    }
}
