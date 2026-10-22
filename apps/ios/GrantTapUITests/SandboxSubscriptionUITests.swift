import XCTest

final class SandboxSubscriptionUITests: XCTestCase {
    func testSandboxOffersCanBeInspectedWithoutRemovingFreeTestingAccess() {
        continueAfterFailure = false
        let app = openSubscription(mode: "sandbox")
        let access = app.descendants(matching: .any)["subscription.testflight-access"].firstMatch
        XCTAssertTrue(access.waitForExistence(timeout: 10))
        let reveal = app.buttons["subscription.show-test-purchases"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 5))
        let buy = app.buttons["subscription.com.ziborov.granttap.personal.solo.monthly"]
        XCTAssertFalse(buy.exists)

        reveal.tap()

        XCTAssertTrue(buy.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sandbox purchases are for testing. Apple does not charge, and free testing access stays active."].exists)
        XCTAssertTrue(access.exists)
        capture("Sandbox catalog remains optional and testing stays free", app: app)
        reveal.tap()
        XCTAssertFalse(buy.exists)
        XCTAssertTrue(access.exists)
    }

    func testAnAccountTestingGrantDoesNotClaimThatPurchasesAreSandboxTransactions() {
        continueAfterFailure = false
        let app = openSubscription(mode: "account")
        XCTAssertTrue(app.staticTexts["Testing access"].waitForExistence(timeout: 10))
        app.buttons["subscription.show-test-purchases"].tap()
        XCTAssertTrue(app.buttons["subscription.com.ziborov.granttap.personal.solo.monthly"].exists)
        XCTAssertTrue(app.staticTexts["No purchase is required for your current testing access. Apple confirms any purchase price and terms."].exists)
        XCTAssertFalse(app.staticTexts["Sandbox — full testing access"].exists)
        XCTAssertFalse(app.staticTexts["Sandbox purchases are for testing. Apple does not charge, and free testing access stays active."].exists)
        capture("Account grant never claims Apple purchases are free", app: app)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }

    private func openSubscription(mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_TEST_LANGUAGE": "en",
            "GRANTTAP_TEST_SANDBOX_PURCHASES": mode, "GRANTTAP_MCP_HTTP_PORT": "0"]
        app.launch()
        app.buttons["Settings"].tap()
        let subscription = app.buttons["Manage subscription"].firstMatch
        for _ in 0..<8 where !subscription.isHittable { app.swipeUp() }
        XCTAssertTrue(subscription.isHittable)
        subscription.tap()
        return app
    }
}
