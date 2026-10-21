import XCTest

final class ConnectionListUITests: XCTestCase {
    func testStartupShowsAConnectionCheckAndOffersRecoveryAfterTimeout() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_TEST_CONNECTION_LIST": "1",
                                 "GRANTTAP_TEST_CONNECTING": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let badge = app.buttons["connection.overview"]
        XCTAssertTrue(badge.waitForExistence(timeout: 10))
        XCTAssertTrue(badge.label.contains("Connecting"), badge.label)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Connecting to relay"
        image.lifetime = .keepAlways
        add(image)
        let offline = NSPredicate(format: "label CONTAINS %@", "Offline")
        expectation(for: offline, evaluatedWith: badge)
        waitForExpectations(timeout: 20)
        badge.tap()
        XCTAssertTrue(app.staticTexts["Alpha Mac"].waitForExistence(timeout: 10))
    }

    func testConnectedRelayDoesNotWaitForAComputer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_TEST_CONNECTION_LIST": "1",
                                 "GRANTTAP_TEST_RELAY_ONLY": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let badge = app.buttons["connection.overview"]
        XCTAssertTrue(badge.waitForExistence(timeout: 10))
        XCTAssertTrue(badge.label.contains("Live"), badge.label)
        badge.tap()
        XCTAssertTrue(app.staticTexts["Relay"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Alpha Mac"].exists)
        XCTAssertTrue(app.staticTexts["Offline"].firstMatch.exists)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Relay connected with computers offline"
        image.lifetime = .keepAlways
        add(image)
    }

    func testConnectionBadgeListsEachMacAndOpensItsOwnHealth() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_TEST_CONNECTION_LIST": "1",
                                 "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()

        let badge = app.buttons["connection.overview"]
        XCTAssertTrue(badge.waitForExistence(timeout: 10))
        XCTAssertTrue(badge.label.contains("Live"), "Relay transport is connected independently of computer freshness")
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
