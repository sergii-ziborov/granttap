import XCTest

#if targetEnvironment(simulator)
/// Runs only against the dedicated encrypted relay fixture on loopback.
final class RelayOfflineUITests: XCTestCase {
    @MainActor
    func testFourProvidersSaveApprovalsAndMessagesWithoutTheComputer() async throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_TEST_LANGUAGE": "en", "GRANTTAP_E2E_ACCEPT_PAIRING": "1"]
        app.launch()
        XCTAssertTrue(app.buttons["approval.details.relay-e2e-codex"].waitForExistence(timeout: 20))
        for _ in 0..<4 {
            let allow = app.buttons["Allow"].firstMatch
            if !allow.isHittable { app.swipeUp() }
            XCTAssertTrue(allow.waitForExistence(timeout: 5))
            let started = Date()
            allow.tap()
            let saving = app.descendants(matching: .any).matching(identifier: "approval.relay-saving")
            let stored = expectation(for: NSPredicate(format: "count == 0"), evaluatedWith: saving)
            await fulfillment(of: [stored], timeout: 5)
            XCTAssertLessThan(Date().timeIntervalSince(started), 6)
        }
        app.buttons["Tasks"].firstMatch.tap()
        for provider in ["codex", "claude", "cursor", "grok"] {
            let chat = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Relay \(provider)")).firstMatch
            XCTAssertTrue(chat.waitForExistence(timeout: 10))
            chat.tap()
            let composer = app.textFields["composer.message"]
            XCTAssertTrue(composer.waitForExistence(timeout: 10))
            composer.tap()
            composer.typeText("Offline transport verification \(provider)")
            let started = Date()
            app.buttons["composer.send"].tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Saved on relay")).firstMatch.waitForExistence(timeout: 5))
            XCTAssertLessThan(Date().timeIntervalSince(started), 6)
            if provider == "grok" {
                composer.tap()
                composer.typeText("Durable relay queue verification")
                app.buttons["composer.queue"].tap()
                let queuedAt = Date()
                app.buttons["composer.queue.add"].tap()
                app.buttons["chat.queue"].tap()
                XCTAssertTrue(app.staticTexts["Saved on relay"].waitForExistence(timeout: 5))
                XCTAssertLessThan(Date().timeIntervalSince(queuedAt), 6)
                app.buttons["chat.queue.done"].tap()
            }
            app.navigationBars.buttons.firstMatch.tap()
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Four providers saved while computer offline"
        shot.lifetime = .keepAlways
        add(shot)
        app.terminate()
    }
}
#endif
