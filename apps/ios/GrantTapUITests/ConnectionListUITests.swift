import XCTest

final class ConnectionListUITests: XCTestCase {
    func testConnectionBadgeListsEachMacAndOpensItsOwnHealth() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_TEST_CONNECTION_LIST": "1",
                                 "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()

        let badge = app.buttons["connection.overview"]
        XCTAssertTrue(badge.waitForExistence(timeout: 10))
        XCTAssertTrue(badge.label.contains("1/2"))
        badge.tap()
        XCTAssertTrue(app.staticTexts["Alpha Mac"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Beta Mac"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "connection.computer.")).count, 2)
        XCTAssertFalse(app.staticTexts["This link"].exists)

        app.buttons["connection.computer.\(String(repeating: "b", count: 32))"].tap()
        XCTAssertTrue(app.staticTexts["Chat list updated"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Reconnect"].exists)
    }
}
