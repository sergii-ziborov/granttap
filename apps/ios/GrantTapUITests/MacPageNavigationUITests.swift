#if targetEnvironment(macCatalyst)
import XCTest

final class MacPageNavigationUITests: XCTestCase {
    func testAccountMeshOpensFromDevicesWithoutALocalComputer() {
        continueAfterFailure = false
        let app = demoApp(openChat: false)
        app.buttons["sidebar.devices"].tap()
        assertCompactHeader(app)
        XCTAssertTrue(app.staticTexts["Account Mesh"].exists)
        XCTAssertTrue(app.buttons["Sign in with passkey"].exists)
        XCTAssertEqual(app.sheets.count, 0)
        XCTAssertTrue(app.buttons["sidebar.devices"].isSelected)
    }

    func testChatMeshOpensTheExistingMainWindowPageAndReturnsToTheList() {
        continueAfterFailure = false
        let app = demoApp(openChat: true)
        let mesh = app.buttons["chat.open-mesh"]
        XCTAssertTrue(mesh.waitForExistence(timeout: 10))
        mesh.tap()
        XCTAssertTrue(app.buttons["project.new-task"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["project.knowledge"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["sidebar.projects"].isSelected)
        XCTAssertEqual(app.sheets.count, 0)
        assertCompactHeader(app)
        app.buttons["page.back"].tap()
        XCTAssertTrue(app.buttons["projects.row.granttap-project-demo"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["project.new-task"].exists)
    }

    func testLogHasTheChatHeaderAndRetainsSearchAndClear() {
        continueAfterFailure = false
        let app = demoApp(openChat: false)
        app.buttons["sidebar.settings"].tap()
        let log = app.buttons["settings.open-log"]
        for _ in 0..<10 where !log.isHittable { app.swipeUp() }
        XCTAssertTrue(log.waitForExistence(timeout: 10))
        log.tap()
        XCTAssertTrue(app.buttons["page.back"].waitForExistence(timeout: 10))
        assertCompactHeader(app)
        XCTAssertTrue(app.textFields["audit.search"].exists)
        XCTAssertTrue(app.buttons["Clear"].exists)
        app.buttons["page.back"].tap()
        XCTAssertTrue(app.buttons["sidebar.settings"].isSelected)
    }

    private func demoApp(openChat: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        XCTAssertTrue(app.buttons["sidebar.settings"].waitForExistence(timeout: 10))
        if openChat {
            app.buttons["sidebar.tasks"].tap()
            let chat = app.buttons["task.task:granttap-project-demo\u{1f}granttap-release-task-demo"]
            XCTAssertTrue(chat.waitForExistence(timeout: 10))
            chat.tap()
        }
        return app
    }

    private func assertCompactHeader(_ app: XCUIApplication) {
        let header = app.descendants(matching: .any)["page.header"].firstMatch
        XCTAssertTrue(header.exists)
        XCTAssertGreaterThan(header.frame.height, 0)
        XCTAssertLessThanOrEqual(header.frame.height, 44)
    }
}
#endif
