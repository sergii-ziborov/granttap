import XCTest

final class TaskScrollUITests: XCTestCase {
    func testNowAndTasksScrollFromCardSurfacesDuringLiveUpdates() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_TEST_TASK_SCROLL": "1",
            "GRANTTAP_E2E_RESET_ARCHIVE": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        for tab in ["Now", "Tasks"] {
            app.tabBars.buttons[tab].tap()
            let cards = app.buttons.matching(NSPredicate(format:
                "identifier BEGINSWITH 'task.' AND label CONTAINS 'Scroll task'"))
            XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
            for _ in 0..<4 {
                guard let candidate = cards.allElementsBoundByIndex.first(where: {
                    $0.isHittable && $0.frame.midY > 350 && $0.frame.midY < app.frame.maxY - 200
                }) else { XCTFail("No card in the scroll gesture area"); return }
                // Lazy lists may reuse indexed accessibility positions after a
                // scroll. Keep the Task identity, not its old array position.
                let visible = app.buttons[candidate.identifier]
                let previous = visible.frame.minY
                let start = visible.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                let end = start.withOffset(CGVector(dx: 18, dy: -240))
                start.press(forDuration: 0.02, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
                XCTAssertTrue(!visible.exists || visible.frame.minY < previous - 40,
                              "vertical movement beginning on a Task must move the list")
            }
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "\(tab) scrolls while task updates arrive"; capture.lifetime = .keepAlways
            add(capture)
        }
    }
}
