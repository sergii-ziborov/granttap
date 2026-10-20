import XCTest

final class HealthDiagnosticsUITests: XCTestCase {
    func testReceivedCortexPacketSeparatesSelectedAndOmittedTokens() {
        continueAfterFailure = false
        let app = openHealth(cortexPacket: true)
        let diagnostics = app.buttons["health.diagnostics"]
        reveal(diagnostics, in: app)
        diagnostics.tap()
        let cortex = app.buttons["Open Cortex diagnostics"]
        reveal(cortex, in: app)
        cortex.tap()
        let endpoint = app.buttons["cortex.endpoint.Workstation"]
        XCTAssertTrue(endpoint.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["A context packet was prepared; agent receipt is not reported."].exists)
        endpoint.tap()
        let packet = app.staticTexts["Latest context packet"]
        reveal(packet, in: app)
        XCTAssertTrue(app.staticTexts["sample-packet"].exists)
        for label in ["Raw estimated tokens", "Selected estimated tokens", "Omitted estimated tokens"] {
            reveal(app.staticTexts[label], in: app)
            XCTAssertTrue(app.staticTexts[label].exists)
        }
        XCTAssertTrue(app.staticTexts["12000"].exists)
        XCTAssertTrue(app.staticTexts["8000"].exists)
        XCTAssertTrue(app.staticTexts["4000"].exists)
        reveal(app.staticTexts["Needs expansion"], in: app)
        XCTAssertTrue(app.staticTexts["Yes"].exists)
    }

    func testDiagnosticsPreservePolicyAndUnknownCortexState() {
        continueAfterFailure = false
        let app = openHealth()
        let diagnostics = app.buttons["health.diagnostics"]
        reveal(diagnostics, in: app)
        diagnostics.tap()
        let policy = app.staticTexts["Reported policy revision"]
        reveal(policy, in: app)
        XCTAssertTrue(policy.exists)
        XCTAssertTrue(app.staticTexts["Enforcement"].exists)
        let cortex = app.buttons["Open Cortex diagnostics"]
        reveal(cortex, in: app)
        cortex.tap()
        XCTAssertTrue(app.navigationBars["Cortex Loom"].waitForExistence(timeout: 5))
        let endpoint = app.buttons["cortex.endpoint.Workstation"]
        XCTAssertTrue(endpoint.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["This computer has not reported its Engine or Cortex status"].firstMatch.exists)
        endpoint.tap()
        XCTAssertTrue(app.staticTexts["Loaded means the library is present. Succeeded means a packet was prepared. Neither proves an agent received or used the packet."].exists)
        XCTAssertTrue(app.staticTexts["16384 tokens"].exists)
        app.buttons["Save Cortex configuration"].tap()
        XCTAssertTrue(app.staticTexts["Request could not be delivered to this computer."].waitForExistence(timeout: 5))
        let libraries = app.staticTexts["Loaded libraries"]
        reveal(libraries, in: app)
        XCTAssertTrue(app.staticTexts["No report"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Latest context packet"].exists)
    }

    func testUnavailableRepositoryShowsReasonProvenanceAndRefreshReturnsToHealth() {
        continueAfterFailure = false
        let app = openHealth(graphState: "unavailable")
        let repository = app.buttons["health.repository-issue.github.com/sergii-ziborov/granttap"]
        reveal(repository, in: app)
        repository.tap()
        XCTAssertTrue(app.staticTexts["Needs attention"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["This Mesh's saved checkout now belongs to another repository. Review its computer binding."].exists)
        XCTAssertTrue(app.staticTexts["Report provenance"].exists)
        XCTAssertTrue(app.staticTexts["2.17.4"].exists)
        XCTAssertTrue(app.staticTexts["bbbbbbbbbbbb"].exists)
        XCTAssertTrue(app.staticTexts["demo-revisio"].exists)
        app.buttons["Refresh architecture"].tap()
        XCTAssertTrue(app.navigationBars["Health"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Report provenance"].exists)
        XCTAssertTrue(repository.exists, "A refresh request must preserve the last reported repository issue")
    }

    private func openHealth(graphState: String? = nil, cortexPacket: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_CAPTURE_TAB": "projects",
                                 "GRANTTAP_TEST_LANGUAGE": "en"]
        if let graphState { app.launchEnvironment["GRANTTAP_TEST_GRAPH_BUILD"] = graphState }
        if cortexPacket { app.launchEnvironment["GRANTTAP_TEST_CORTEX_PACKET"] = "1" }
        app.launch()
        let project = app.buttons["projects.row.granttap-project-demo"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let health = app.buttons["project.health"]
        reveal(health, in: app)
        health.tap()
        XCTAssertTrue(app.navigationBars["Health"].waitForExistence(timeout: 5))
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
}
