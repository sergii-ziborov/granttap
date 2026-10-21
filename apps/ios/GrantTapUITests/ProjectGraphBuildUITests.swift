import XCTest

/// Synthetic Mesh states validate the visible request lifecycle without a live account.
final class ProjectGraphBuildUITests: XCTestCase {
    func testEmptyGraphOffersAReadableBuildActionAndExplainsItsLifecycle() {
        let app = open(state: "idle")
        let build = app.buttons["project.graph.analyze"]
        XCTAssertTrue(build.waitForExistence(timeout: 5))
        XCTAssertTrue(build.isEnabled)
        XCTAssertEqual(build.label, "Build architecture now")
        XCTAssertTrue(app.staticTexts["Architecture is not built yet"].exists)
        XCTAssertEqual(progress(app).count, 0)
        capture(app, "Graph empty ready to build")
        app.buttons["project.graph.build-info"].tap()
        XCTAssertTrue(app.navigationBars["How architecture updates"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["On your computers"].exists)
        XCTAssertTrue(app.staticTexts["Keeping the report current"].exists)
        XCTAssertTrue(app.staticTexts["Available offline"].exists)
        capture(app, "Graph build information")
    }

    func testEmptyPendingGraphShowsOneIntegratedProgressStateWithoutDisabledBuildAction() {
        let app = open(state: "pending")
        XCTAssertTrue(progress(app).firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(progress(app).count, 1)
        capture(app, "Graph empty building")
        XCTAssertEqual(indicatorFrames(in: status(app)).count, 1)
        XCTAssertFalse(app.buttons["project.graph.analyze"].exists)
        XCTAssertTrue(app.staticTexts["Building architecture…"].exists)
        let card = status(app)
        XCTAssertTrue(card.exists)
        XCTAssertTrue(card.frame.contains(progress(app).firstMatch.frame))
    }

    func testFailedBuildCanRetryAndExplainsWhenNoComputerCanReceiveIt() {
        let app = open(state: "failure")
        let retry = app.buttons["project.graph.analyze"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(retry.isEnabled)
        XCTAssertEqual(retry.label, "Retry architecture build")
        XCTAssertTrue(app.staticTexts["Architecture could not refresh"].exists)
        XCTAssertEqual(progress(app).count, 0)
        capture(app, "Graph failed with retry")
        retry.tap()
        XCTAssertTrue(app.staticTexts["No connected computer can receive this Mesh's analysis request."]
            .waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Computer connection needed"].exists)
        XCTAssertTrue(retry.isEnabled)
        XCTAssertEqual(progress(app).count, 0)
        capture(app, "Graph disconnected with retry")
    }

    func testCachedArchitectureRemainsInspectableWhileItRebuilds() {
        let app = open(state: "cached-pending")
        XCTAssertTrue(progress(app).firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(progress(app).count, 1)
        XCTAssertTrue(app.staticTexts["Refreshing architecture…"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["project.graph.saved-report"].exists)
        let report = app.buttons["architecture.fullscreen.github.com/sergii-ziborov/granttap"]
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        capture(app, "Graph last report during rebuild")
        report.tap()
        XCTAssertTrue(app.buttons["Close graph"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["architecture.search"].exists)
        app.buttons["Close graph"].tap()
        let towers = app.buttons["architecture.towers.github.com/sergii-ziborov/granttap"]
        XCTAssertTrue(towers.waitForExistence(timeout: 5))
        towers.tap()
        CodeCityJourney.waitForViewer(app)
        app.buttons["Close code towers"].tap()
        XCTAssertTrue(progress(app).firstMatch.waitForExistence(timeout: 5))
    }

    func testHealthKeepsProgressAndGraphNavigationTogetherAboveRepositoryRows() {
        let app = open(state: "pending", health: true)
        XCTAssertTrue(progress(app).firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(progress(app).count, 1)
        capture(app, "Health building architecture")
        XCTAssertEqual(indicatorFrames(in: status(app)).count, 1)
        XCTAssertFalse(app.buttons["health.code-towers.refresh"].exists)
        let graph = app.buttons["Open graph and analysis status"]
        XCTAssertTrue(graph.exists)
        XCTAssertTrue(graph.isHittable)
        graph.tap()
        XCTAssertTrue(app.navigationBars["Graph"].waitForExistence(timeout: 5))
        XCTAssertEqual(progress(app).count, 1)
    }

    private func open(state: String, health: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "GRANTTAP_DEMO": "1", "GRANTTAP_CAPTURE_TAB": "projects",
            "GRANTTAP_TEST_LANGUAGE": "en", "GRANTTAP_TEST_GRAPH_BUILD": state,
        ]
        app.launch()
        let project = app.buttons["projects.row.granttap-project-demo"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let destination = app.buttons[health ? "project.health" : "project.openGraph"]
        for _ in 0..<5 where !destination.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        XCTAssertTrue(destination.isHittable)
        destination.tap()
        XCTAssertTrue(app.navigationBars[health ? "Health" : "Graph"].waitForExistence(timeout: 5))
        return app
    }

    private func status(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "project.graph.status").firstMatch
    }

    private func progress(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "project.graph.progress")
    }

    private func indicatorFrames(in card: XCUIElement) -> Set<String> {
        let indicators = card.descendants(matching: .activityIndicator).allElementsBoundByIndex
        let frames = indicators.map { NSCoder.string(for: $0.frame) }
        let evidence = XCTAttachment(string: frames.joined(separator: "\n"))
        evidence.name = "Visible loader frames"
        evidence.lifetime = .keepAlways
        add(evidence)
        // SwiftUI and its native spinner expose one frame twice, with subpixel rounding differences.
        return Set(indicators.map { NSCoder.string(for: $0.frame.integral) })
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
