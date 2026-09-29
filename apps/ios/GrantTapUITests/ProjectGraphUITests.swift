import XCTest

final class ProjectGraphUITests: XCTestCase {
    func testExecutionRepositoryHasItsOwnProjectInsideTheLinkedGroup() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "GRANTTAP_DEMO": "1", "GRANTTAP_CAPTURE_TAB": "projects",
            "GRANTTAP_TEST_SOLUTION": "1", "GRANTTAP_TEST_LANGUAGE": "en",
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["Linked Mesh spaces · granttap"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["projects.row.granttap-project-demo"].exists)
        XCTAssertTrue(app.buttons["projects.row.granttap-runtime-demo"].exists)
    }

    func testMeshInviteIsInsideMeshWithoutCompanyControls() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "GRANTTAP_DEMO": "1", "GRANTTAP_CAPTURE_TAB": "projects",
            "GRANTTAP_TEST_LANGUAGE": "en",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["projects.row.granttap-project-demo"].waitForExistence(timeout: 10))
        for _ in 0..<8 where !app.buttons["mesh.join"].exists { app.swipeUp() }
        XCTAssertTrue(app.buttons["mesh.join"].exists)
        XCTAssertFalse(app.buttons["projects.company-accounts"].exists)
    }

    private func openDemoProject(graph: Bool = false, largeGraph: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var environment = [
            "GRANTTAP_DEMO": "1", "GRANTTAP_CAPTURE_TAB": "projects",
            "GRANTTAP_TEST_LANGUAGE": "en",
        ]
        if graph { environment["GRANTTAP_TEST_GRAPH"] = "1" }
        if largeGraph { environment["GRANTTAP_TEST_GRAPH_LARGE"] = "1" }
        app.launchEnvironment = environment
        app.launch()
        let project = app.buttons["projects.row.granttap-project-demo"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        return app
    }

    func testProjectOpensFullScreenGraph() {
        continueAfterFailure = false
        let app = openDemoProject()

        let graph = app.buttons["project.openGraph"]
        XCTAssertTrue(graph.waitForExistence(timeout: 10))
        graph.tap()

        XCTAssertTrue(app.navigationBars["Graph"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Architecture unavailable"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Repository topology"].exists)
    }

    func testObservedGraphOpensInFullScreenWithSearchAndRealScene() {
        continueAfterFailure = false
        let app = openDemoProject(graph: true)
        let graph = app.buttons["project.openGraph"]
        XCTAssertTrue(graph.waitForExistence(timeout: 10))
        graph.tap()
        let open = app.buttons["architecture.fullscreen.github.com/sergii-ziborov/granttap"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        XCTAssertTrue(app.buttons["Close graph"].waitForExistence(timeout: 10))
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Full-screen Weavatrix graph"
        image.lifetime = .keepAlways
        add(image)
        let search = app.textFields["architecture.search"]
        XCTAssertTrue(search.exists, app.debugDescription)
        search.tap()
        search.typeText("Watch")
        let watch = app.buttons["architecture.result.watch"]
        XCTAssertTrue(watch.waitForExistence(timeout: 5))
        watch.tap()
        XCTAssertTrue(app.staticTexts["architecture.inspector.title"].waitForExistence(timeout: 5),
                      app.debugDescription)
    }

    func testHealthOpensRepoLensStyleCodeTowersInFullScreen() {
        continueAfterFailure = false
        let app = openDemoProject(graph: true)
        let health = app.buttons["project.health"]
        for _ in 0..<5 where !health.exists { app.swipeUp() }
        XCTAssertTrue(health.waitForExistence(timeout: 10))
        health.tap()
        XCTAssertTrue(app.navigationBars["Health"].waitForExistence(timeout: 10))
        let towers = app.buttons["health.code-towers.github.com/sergii-ziborov/granttap"]
        for _ in 0..<5 where !towers.exists { app.swipeUp() }
        XCTAssertTrue(towers.waitForExistence(timeout: 10), app.debugDescription)
        towers.tap()
        XCTAssertTrue(app.buttons["Close code towers"].waitForExistence(timeout: 10))
        let search = app.descendants(matching: .any)["code-towers.search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Health code towers full screen"
        image.lifetime = .keepAlways
        add(image)
        search.tap()
        search.typeText("HealthView")
        let file = app.buttons.containing(.staticText, identifier: "apps/ios/GrantTap/HealthView.swift")
            .firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 5))
        file.tap()
        XCTAssertTrue(app.staticTexts["code-towers.inspector.path"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["code-towers.inspector.path"].label.contains("HealthView.swift"))
        search.tap()
        search.typeText("Relay service")
        let external = app.buttons.containing(.staticText, identifier: "Relay service").firstMatch
        XCTAssertTrue(external.waitForExistence(timeout: 5))
        external.tap()
        XCTAssertTrue(app.staticTexts["code-towers.inspector.external"].waitForExistence(timeout: 5))
    }

    func testHealthNavigatesALargePartialCodeCity() {
        continueAfterFailure = false
        let app = openDemoProject(largeGraph: true)
        let health = app.buttons["project.health"]
        for _ in 0..<5 where !health.exists { app.swipeUp() }
        XCTAssertTrue(health.waitForExistence(timeout: 10))
        health.tap()
        XCTAssertTrue(app.staticTexts["Partial map"].waitForExistence(timeout: 10))
        let towers = app.buttons["health.code-towers.github.com/sergii-ziborov/granttap"]
        XCTAssertTrue(towers.waitForExistence(timeout: 10))
        towers.tap()
        XCTAssertTrue(app.buttons["Close code towers"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS %@", "650/653"
        )).firstMatch.exists)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Large partial code city"
        image.lifetime = .keepAlways
        add(image)
        let search = app.descendants(matching: .any)["code-towers.search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Source649")
        let file = app.buttons.containing(.staticText, identifier:
            "apps/ios/GrantTap/Features/Area25/Source649.swift").firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 10))
        file.tap()
        XCTAssertTrue(app.staticTexts["code-towers.inspector.path"].waitForExistence(timeout: 10))
        app.buttons["Close code towers"].tap()
        XCTAssertTrue(app.navigationBars["Health"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Partial map"].exists)
    }

    func testStatisticsHasTaskDiagramAndEvidenceBars() {
        continueAfterFailure = false
        let app = openDemoProject()
        let statistics = app.buttons["project.statistics"]
        XCTAssertTrue(statistics.waitForExistence(timeout: 10))
        statistics.tap()
        XCTAssertTrue(app.navigationBars["Statistics"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Tasks by state"].exists)
        XCTAssertTrue(app.staticTexts["Activity and evidence"].exists)
        let chart = app.buttons["statistics.tasks.chart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        chart.tap()
        XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 10))
    }

    func testCortexCanBeConfiguredBeforeEngineReports() {
        continueAfterFailure = false
        let app = openDemoProject()
        let cortex = app.buttons["project.cortex"]
        for _ in 0..<5 where !cortex.exists { app.swipeUp() }
        XCTAssertTrue(cortex.waitForExistence(timeout: 10))
        cortex.tap()
        XCTAssertTrue(app.navigationBars["Cortex Loom"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No report"].firstMatch.exists)
        XCTAssertTrue(app.switches["Enabled for this Mesh"].waitForExistence(timeout: 10))
    }

    func testRestrictionsOpenAnEditableMeasurableRule() {
        continueAfterFailure = false
        let app = openDemoProject()
        let restrictions = app.buttons["project.restrictions"]
        for _ in 0..<6 where !restrictions.exists { app.swipeUp() }
        XCTAssertTrue(restrictions.waitForExistence(timeout: 10))
        restrictions.tap()
        XCTAssertTrue(app.navigationBars["Restrictions"].waitForExistence(timeout: 10))
        let add = app.buttons["Add rule"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        XCTAssertTrue(app.navigationBars["Restriction rule"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["Rule name"].exists)
    }

    func testAutoAcceptLinksToActionRules() {
        continueAfterFailure = false
        let app = openDemoProject()
        let autoAccept = app.buttons["project.auto-accept"]
        for _ in 0..<6 where !autoAccept.exists { app.swipeUp() }
        XCTAssertTrue(autoAccept.waitForExistence(timeout: 10))
        autoAccept.tap()
        XCTAssertTrue(app.navigationBars["Auto-accept"].waitForExistence(timeout: 10))
        let rules = app.buttons["project.auto-accept.rules"]
        XCTAssertTrue(rules.waitForExistence(timeout: 10))
        rules.tap()
        XCTAssertTrue(app.navigationBars["Action rules"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["governance.enforcement"].exists)
    }

    func testKnowledgeConnectsObservedCommitToItsGraph() {
        continueAfterFailure = false
        let app = openDemoProject(graph: true)
        let knowledge = app.buttons["project.knowledge"]
        XCTAssertTrue(knowledge.waitForExistence(timeout: 10))
        knowledge.tap()
        XCTAssertTrue(app.navigationBars["Knowledge"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Decisions"].exists)

        let revisions = app.staticTexts["Repository revisions"]
        for _ in 0..<5 where !revisions.exists { app.swipeUp() }
        XCTAssertTrue(revisions.waitForExistence(timeout: 5))
        let commit = app.staticTexts[String(repeating: "b", count: 12)].firstMatch
        XCTAssertTrue(commit.waitForExistence(timeout: 5))
        commit.tap()
        XCTAssertTrue(app.navigationBars["Revision"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[String(repeating: "b", count: 40)].exists)
        XCTAssertTrue(app.buttons["Open repository graph"].exists)
    }

    func testStatisticsUsageAndCapabilityStatesAreInspectable() {
        continueAfterFailure = false
        let app = openDemoProject(graph: true)
        let statistics = app.buttons["project.statistics"]
        XCTAssertTrue(statistics.waitForExistence(timeout: 10))
        statistics.tap()
        XCTAssertTrue(app.staticTexts["Tokens and resources"].waitForExistence(timeout: 10))
        let tokens = app.buttons.containing(.staticText, identifier: "Tokens").firstMatch
        XCTAssertTrue(tokens.exists)
        tokens.tap()
        XCTAssertTrue(app.navigationBars["Usage"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let skills = app.buttons.containing(.staticText, identifier: "Skills and MCP").firstMatch
        for _ in 0..<5 where !skills.exists { app.swipeUp() }
        XCTAssertTrue(skills.waitForExistence(timeout: 5))
        skills.tap()
        XCTAssertTrue(app.navigationBars["Tools & Skills"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Built-in Mesh intelligence"].exists)
        let mcp = app.staticTexts["MCP servers"]
        for _ in 0..<5 where !mcp.exists { app.swipeUp() }
        XCTAssertTrue(mcp.waitForExistence(timeout: 5))
    }

    func testMemberInviteShowsProjectScopeAndLinkLifetime() {
        continueAfterFailure = false
        let app = openDemoProject()
        let members = app.buttons["project.members"]
        for _ in 0..<5 where !members.exists { app.swipeUp() }
        XCTAssertTrue(members.waitForExistence(timeout: 10))
        members.tap()
        XCTAssertTrue(app.navigationBars["Members / Computers"].waitForExistence(timeout: 10))
        let invite = app.buttons["members.invite"]
        for _ in 0..<5 where !invite.exists { app.swipeUp() }
        XCTAssertTrue(invite.waitForExistence(timeout: 5))
        invite.tap()
        XCTAssertTrue(app.navigationBars["Invite a person"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Mesh spaces and repositories"].exists)
        XCTAssertTrue(app.staticTexts["github.com/sergii-ziborov/granttap"].exists)
        let expiry = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Invite expires after"))
            .firstMatch
        for _ in 0..<5 where !expiry.exists { app.swipeUp() }
        XCTAssertTrue(expiry.waitForExistence(timeout: 5))
    }

    func testRecommendedRestrictionOpensItsRuleEditor() {
        continueAfterFailure = false
        let app = openDemoProject()
        let restrictions = app.buttons["project.restrictions"]
        for _ in 0..<6 where !restrictions.exists { app.swipeUp() }
        XCTAssertTrue(restrictions.waitForExistence(timeout: 10))
        restrictions.tap()
        let preset = app.buttons.containing(.staticText, identifier: "File line limit").firstMatch
        XCTAssertTrue(preset.waitForExistence(timeout: 10))
        preset.tap()
        XCTAssertTrue(app.navigationBars["Restriction rule"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["Rule name"].exists)
    }
}
