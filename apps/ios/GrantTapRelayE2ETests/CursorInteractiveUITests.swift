import XCTest

#if targetEnvironment(simulator)
/// Opt-in live test against the dedicated Cursor task and local encrypted relay.
final class CursorInteractiveUITests: XCTestCase {
    @MainActor
    func testCursorHistoryAfterComputerRestart() async throws {
        try await requireDedicatedLiveFixture()
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_TEST_LANGUAGE": "en", "GRANTTAP_E2E_ACCEPT_PAIRING": "1"]
        app.launch()
        try assertReadableCursorChat(app)
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:42202/status")!)
        let state = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertGreaterThan(state["activityRequests"] as? Int ?? 0, 0)
        app.terminate()
    }

    @MainActor
    func testCursorQuestionProtocolRoundTrip() async throws {
        try await requireDedicatedLiveFixture()
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_TEST_LANGUAGE": "en", "GRANTTAP_E2E_ACCEPT_PAIRING": "1"]
        app.launch()
        var request = URLRequest(url: URL(string: "http://127.0.0.1:42202/question")!)
        request.httpMethod = "POST"
        _ = try await URLSession.shared.data(for: request)
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "approval.details.cursor-question-")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.tap()
        let option = app.buttons["approval.question.option.0.0"]
        XCTAssertTrue(option.waitForExistence(timeout: 10))
        XCTAssertTrue(option.label.contains("Check marker"))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Cursor question protocol in GrantTap"
        shot.lifetime = .keepAlways
        add(shot)
        option.tap()
        app.buttons["approval.question.submit"].tap()
        let done = app.navigationBars.buttons["Done"].firstMatch
        if done.exists { done.tap() }
        try await verifyCompletion()
        app.terminate()
    }

    @MainActor
    func testNativeCursorIdeMigrationPermissionRoundTrip() async throws {
        try await requireDedicatedLiveFixture()
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_TEST_LANGUAGE": "en", "GRANTTAP_E2E_ACCEPT_PAIRING": "1"]
        app.launch()
        var request = URLRequest(url: URL(string: "http://127.0.0.1:42202/migration")!)
        request.httpMethod = "POST"
        _ = try await URLSession.shared.data(for: request)
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "approval.details.cursor-permission-")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 180))
        XCTAssertTrue(card.label.contains("cursor-migrated-approved-marker.txt"))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Original Cursor Task receives native permission"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["Allow"].firstMatch.tap()
        try await verifyCompletion()
        try assertReadableCursorChat(app)
        app.terminate()
        app.launch()
        try assertReadableCursorChat(app)
        app.terminate()
    }

    @MainActor
    func testNativeCursorPermissionRoundTrip() async throws {
        try await requireDedicatedLiveFixture()
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_TEST_LANGUAGE": "en", "GRANTTAP_E2E_ACCEPT_PAIRING": "1"]
        app.launch()
        var request = URLRequest(url: URL(string: "http://127.0.0.1:42202/permission")!)
        request.httpMethod = "POST"
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "approval.details.cursor-permission-")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 150))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Real Cursor permission in GrantTap"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["Allow"].firstMatch.tap()
        let saving = app.descendants(matching: .any).matching(identifier: "approval.relay-saving")
        await fulfillment(of: [expectation(for: NSPredicate(format: "count == 0"), evaluatedWith: saving)], timeout: 5)
        try await verifyCompletion()
        app.terminate()
    }

    private func requireDedicatedLiveFixture() async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:42202/status")!)
        request.timeoutInterval = 2
        let data: Data
        do { (data, _) = try await URLSession.shared.data(for: request) }
        catch { throw XCTSkip("Requires the dedicated local Cursor verification fixture.") }
        let state = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (state?["scope"] as? String)?.hasPrefix("real Cursor ACP,") == true else {
            throw XCTSkip("Live provider verification is separate from the offline relay fixture.")
        }
    }

    @MainActor
    private func assertReadableCursorChat(_ app: XCUIApplication) throws {
        let tasks = app.buttons["Tasks"].firstMatch
        XCTAssertTrue(tasks.waitForExistence(timeout: 15))
        tasks.tap()
        let chat = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Cursor interactive verification")).firstMatch
        XCTAssertTrue(chat.waitForExistence(timeout: 15))
        chat.tap()
        let answer = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Migrated verification complete")).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 20), "The original Task must reopen with its completed Cursor answer")
        XCTAssertFalse(app.staticTexts["Opening the encrypted chat…"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Cursor history opens after approval and app restart"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func verifyCompletion() async throws {
        for _ in 0..<90 {
            let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:42202/status")!)
            let state = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            if let result = state["result"] as? [String: Any] {
                XCTAssertEqual(result["ok"] as? Bool, true)
                XCTAssertEqual(result["completedMarker"] as? Bool, true)
                if let retained = result["stableTaskRetained"] as? Bool { XCTAssertTrue(retained) }
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        XCTFail("The native caller did not receive the controller's decision.")
    }
}
#endif
