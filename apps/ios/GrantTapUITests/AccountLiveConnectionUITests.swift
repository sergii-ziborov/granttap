import XCTest

final class AccountLiveConnectionUITests: XCTestCase {
    func testAccountConnectionReceivesFreshComputerActivity() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        #if targetEnvironment(simulator)
        app.launchEnvironment = ["GRANTTAP_TEST_CONNECTION_LIST": "1",
                                 "GRANTTAP_TEST_LANGUAGE": "en"]
        #else
        // Exercise the owner's saved account without signing out, pairing anew,
        // changing approval policy, or clearing the installed app's history.
        app.launchEnvironment = ["GRANTTAP_TEST_LANGUAGE": "en", "GRANTTAP_TEST_DIAGNOSTICS": "1"]
        #endif
        app.launch()
        let badge = app.buttons["connection.overview"]
        XCTAssertTrue(badge.waitForExistence(timeout: 20))
        let live = XCTNSPredicateExpectation(predicate: NSPredicate(
            format: "label CONTAINS[c] %@ AND NOT label BEGINSWITH %@", "Live", "0/"), object: badge)
        let result = XCTWaiter.wait(for: [live], timeout: 40)
        let evidence = XCTAttachment(screenshot: badge.screenshot())
        evidence.name = "Authenticated computer connection status"
        evidence.lifetime = .keepAlways
        add(evidence)
        XCTAssertEqual(result, .completed, "Saved account must receive fresh computer activity.")
        #if !targetEnvironment(simulator)
        let preloaded = XCTNSPredicateExpectation(predicate: NSPredicate(
            format: "value == %@", "ready"), object: badge)
        XCTAssertEqual(XCTWaiter.wait(for: [preloaded], timeout: 90), .completed,
                       "Every Now chat must have its current history head cached before it is opened.")
        let codex = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Codex")).count
        badge.tap()
        let computers = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "connection.computer."))
        XCTAssertTrue(computers.firstMatch.waitForExistence(timeout: 10))
        let state: [String: Any] = ["codexRows": codex,
            "computers": computers.allElementsBoundByIndex.map { $0.label }]
        let data = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
        let details = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        details.name = "Connection health without chat contents"
        details.lifetime = .keepAlways
        add(details)
        XCTAssertGreaterThan(codex, 0, "The Mac's discovered Codex chats must reach the phone.")
        #endif
    }
}
