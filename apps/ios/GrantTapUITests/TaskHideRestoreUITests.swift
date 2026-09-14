import XCTest

final class TaskHideRestoreUITests: XCTestCase {
    func testHiddenTaskCanBeRestoredFromTasks() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "GRANTTAP_DEMO": "1",
            "GRANTTAP_CAPTURE_TAB": "tasks",
            "GRANTTAP_E2E_RESET_ARCHIVE": "1",
            "GRANTTAP_TEST_LANGUAGE": "en",
        ]
        app.launch()

        let task = app.buttons["task.task:granttap-project-demo\u{001F}granttap-pairing-task-demo"]
        XCTAssertTrue(task.waitForExistence(timeout: 10))

        openContextMenu(on: task, until: app.buttons["Hide"])
        tap(app.buttons["Hide"], until: { !task.exists })
        XCTAssertTrue(task.waitForNonExistence(timeout: 5))

        let hidden = app.buttons["tasks.hidden"]
        XCTAssertTrue(hidden.waitForExistence(timeout: 5))
        tap(hidden, until: { app.buttons["task.restore.granttap-claude-demo"].exists })

        let restore = app.buttons["task.restore.granttap-claude-demo"]
        XCTAssertTrue(restore.waitForExistence(timeout: 10))
        tap(restore, until: { !restore.exists })

        let hiddenNavigation = app.navigationBars["Hidden tasks"]
        if hiddenNavigation.exists {
            hiddenNavigation.buttons.firstMatch.tap()
        }
        XCTAssertTrue(task.waitForExistence(timeout: 5))
    }

    /// A long press only opens the menu once the list has stopped rebuilding,
    /// and pressing the element's own frame misses while it is being replaced.
    /// Pressing the middle of its current frame, and asking again, is stable.
    private func openContextMenu(
        on element: XCUIElement, until item: XCUIElement,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for _ in 0..<4 {
            guard !item.exists else { return }
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 1.2)
            if item.waitForExistence(timeout: 4) { return }
        }
        XCTFail("the context menu never opened", file: file, line: line)
    }

    /// Taps until the interface actually moved on.
    ///
    /// SwiftUI rebuilds these lists while they animate, so an element found a
    /// moment ago can be replaced before the tap lands, and a partly scrolled
    /// row reports itself as not hittable. Tapping the centre of the frame and
    /// re-checking the outcome survives both.
    private func tap(
        _ element: XCUIElement, until settled: () -> Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for _ in 0..<4 {
            guard !settled() else { return }
            guard element.waitForExistence(timeout: 5) else { continue }
            if element.isHittable {
                element.tap()
            } else {
                element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            let deadline = Date().addingTimeInterval(4)
            while Date() < deadline {
                if settled() { return }
                _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: 0.3)
            }
        }
        XCTAssertTrue(settled(), "the interface never settled after the tap", file: file, line: line)
    }
}
