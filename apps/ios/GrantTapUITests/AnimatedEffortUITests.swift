import XCTest

final class AnimatedEffortUITests: XCTestCase {
    func testEffortSliderPersistsAndRespectsSelectedModelsLevels() {
        continueAfterFailure = false
        let app = launchChat()
        press(app.buttons["composer.model"])
        let slider = app.sliders["composer.effort.slider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "Every supported model needs the shared effort slider.")
        XCTAssertTrue(control(app, "composer.effort").label.contains("Medium"),
                      "The reported current effort must display before creating an override.")
        drag(slider, from: 0.2, to: 0)
        expectEffort("Low", in: app)
        capture(app, "Animated Low effort")
        drag(slider, from: 0, to: 0.6)
        expectEffort("Extra High", in: app)
        capture(app, "Animated Extra High effort")
        drag(slider, from: 0.6, to: 1)
        expectEffort("Ultra", in: app)
        capture(app, "Animated Ultra effort")
        press(app.buttons["composer.model.done"])
        XCTAssertFalse(slider.exists)
        press(app.buttons["composer.model"])
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        expectEffort("Ultra", in: app)
        press(app.buttons["composer.model.select.gpt-6-luna"])
        let confirm = app.windows.buttons["Switch model"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        press(app.windows.buttons["Cancel"].firstMatch)
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        expectEffort("Ultra", in: app)
        press(app.buttons["composer.model.select.gpt-6-luna"])
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        press(confirm)
        XCTAssertTrue(app.buttons["composer.model"].waitForExistence(timeout: 5))
        press(app.buttons["composer.model"])
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        drag(slider, from: 0.25, to: 1)
        expectEffort("Maximum", in: app)
        press(app.buttons["composer.effort.reset"])
        expectEffort("Medium", in: app)
        press(app.buttons["composer.model.done"])
        XCTAssertFalse(slider.exists)
        app.terminate()
    }

    func testTaskMenuAndTaskControlsOfferTheSameTransferAndWorkingModelDone() {
        continueAfterFailure = false
        let app = launchChat(transfer: true)
        press(control(app, "chat.menu"))
        let transfer = menuItem(app, "chat.menu.transfer", "Transfer to…")
        XCTAssertTrue(transfer.waitForExistence(timeout: 5))
        press(transfer)
        XCTAssertTrue(app.buttons["handoff.close"].waitForExistence(timeout: 5))
        press(app.buttons["handoff.close"])
        press(control(app, "chat.menu"))
        press(menuItem(app, "chat.menu.controls", "Task controls"))
        let handoff = app.buttons["chat.controls.transfer"]
        for _ in 0..<8 where !handoff.isHittable { scroll(app, down: true) }
        XCTAssertTrue(handoff.isHittable)
        capture(app, "Shared Task controls and transfer")
        press(handoff)
        XCTAssertTrue(app.buttons["handoff.close"].waitForExistence(timeout: 5))
        press(app.buttons["handoff.close"])
        let model = app.buttons.matching(identifier: "composer.model")
        for _ in 0..<8 where !model.allElementsBoundByIndex.contains(where: \.isHittable) {
            scroll(app, down: false)
        }
        let visible = model.allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(visible)
        press(visible!)
        XCTAssertTrue(app.sliders["composer.effort.slider"].waitForExistence(timeout: 5))
        press(app.buttons["composer.model.done"])
        XCTAssertFalse(app.sliders["composer.effort.slider"].exists)
        XCTAssertTrue(app.buttons["chat.controls.done"].isHittable,
                      "Model Done closes its own popover, preserving Task controls.")
        press(app.buttons["chat.controls.done"])
        let returned = expectation(for: NSPredicate(format: "hittable == true"),
                                   evaluatedWith: control(app, "chat.menu"))
        wait(for: [returned], timeout: 5)
        app.terminate()
    }

    private func scroll(_ app: XCUIApplication, down: Bool) {
        #if targetEnvironment(macCatalyst)
        app.collectionViews.allElementsBoundByIndex.last!.scroll(byDeltaX: 0, deltaY: down ? -350 : 350)
        #else
        if down { app.swipeUp() } else { app.swipeDown() }
        #endif
    }

    private func control(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func expectEffort(_ label: String, in app: XCUIApplication) {
        let displayed = expectation(for: NSPredicate(format: "label CONTAINS %@", label),
                                    evaluatedWith: control(app, "composer.effort"))
        wait(for: [displayed], timeout: 5)
    }

    private func drag(_ slider: XCUIElement, from: Double, to: Double) {
        let origin = slider.coordinate(withNormalizedOffset: .zero)
        let inset = min(19, slider.frame.width / 2)
        let width = slider.frame.width - inset * 2
        let start = origin.withOffset(CGVector(dx: inset + width * from, dy: slider.frame.height / 2))
        let end = origin.withOffset(CGVector(dx: inset + width * to, dy: slider.frame.height / 2))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    private func menuItem(_ app: XCUIApplication, _ id: String, _ title: String) -> XCUIElement {
        let identified = control(app, id)
        if identified.waitForExistence(timeout: 1) { return identified }
        #if targetEnvironment(macCatalyst)
        return app.menuItems[title]
        #else
        return app.buttons[title]
        #endif
    }

    private func launchChat(transfer: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_OPEN_SESSION": "1",
            "GRANTTAP_TEST_MODELS": "1", "GRANTTAP_TEST_LANGUAGE": "en",
            "GRANTTAP_TEST_CURRENT_EFFORT": "medium"]
        if transfer { app.launchEnvironment["GRANTTAP_TEST_TRANSFER_CONTROLS"] = "1" }
        #if targetEnvironment(macCatalyst)
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO"]
        #endif
        app.launch()
        app.activate()
        #if targetEnvironment(macCatalyst)
        if !app.buttons["composer.model"].waitForExistence(timeout: 5) {
            press(app.buttons["sidebar.tasks"])
            let task = app.buttons["task.task:granttap-project-demo\u{1f}granttap-release-task-demo"]
            XCTAssertTrue(task.waitForExistence(timeout: 10))
            press(task)
        }
        #endif
        XCTAssertTrue(app.buttons["composer.model"].waitForExistence(timeout: 15))
        return app
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
