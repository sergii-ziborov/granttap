import XCTest

final class ReportPreviewUITests: XCTestCase {
    func testReportPreviewsBothFormatsAndDoneClosesOnlyReport() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_OPEN_SESSION": "1",
                                 "GRANTTAP_TEST_LANGUAGE": "en"]
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
        openReport(app)
        XCTAssertTrue(control(app, "report.preview.pdf").waitForExistence(timeout: 10),
                      "Report must show the actual PDF before sharing.")
        XCTAssertTrue(app.buttons["report.share"].isHittable)
        capture(app, "Report PDF preview")
        press(app.segmentedControls.buttons["CSV"])
        let csv = app.textViews["report.preview.csv"]
        XCTAssertTrue(csv.waitForExistence(timeout: 10))
        XCTAssertTrue((csv.value as? String)?.contains("Figure,Value,Note") == true,
                      "CSV preview shows exported cells, not a summary substitute.")
        XCTAssertTrue(app.buttons["report.share"].isEnabled)
        capture(app, "Report CSV preview")
        press(app.segmentedControls.buttons["PDF"])
        XCTAssertTrue(control(app, "report.preview.pdf").waitForExistence(timeout: 5))
        press(app.buttons["report.done"])
        XCTAssertFalse(control(app, "report.preview.pdf").exists)
        let returned = expectation(for: NSPredicate(format: "hittable == true"),
                                   evaluatedWith: control(app, "chat.menu"))
        wait(for: [returned], timeout: 5)
        openReport(app)
        XCTAssertTrue(control(app, "report.preview.pdf").waitForExistence(timeout: 10))
        press(app.buttons["report.done"])
        app.terminate()
    }

    private func openReport(_ app: XCUIApplication) {
        press(control(app, "chat.menu"))
        #if targetEnvironment(macCatalyst)
        press(app.menuItems["Report (PDF or CSV)…"])
        #else
        press(app.buttons["chat.menu.report"])
        #endif
    }

    private func control(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
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
