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
        XCTAssertTrue(app.descendants(matching: .any)["project.graph.status"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["project.graph.analyze"].exists)
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
        let app = CodeCityJourney.openTowers(sections: false)
        app.webViews.buttons["Fit"].firstMatch.tap()
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Shared Repo Lens code city on iPhone"
        image.lifetime = .keepAlways
        add(image)
        CodeCityJourney.search("HealthView", in: app)
        app.webViews.buttons["apps/ios/GrantTap/HealthView.swift"].tap()
        XCTAssertTrue(app.webViews.staticTexts["apps/ios/GrantTap/HealthView.swift"].waitForExistence(timeout: 5))
        CodeCityJourney.search("Relay service", in: app)
        let external = app.webViews.buttons.matching(NSPredicate(
            format: "label CONTAINS %@", "Relay service")).firstMatch
        XCTAssertTrue(external.waitForExistence(timeout: 5)); external.tap()
        CodeCityJourney.control("Health", in: app).tap()
        XCTAssertTrue(app.webViews.staticTexts["Health evidence"].waitForExistence(timeout: 5))
    }

    func testHealthNavigatesALargePartialCodeCity() {
        continueAfterFailure = false
        DenseCodeCityJourney.run(in: self)
    }

    func testDenseCodeCityOverviewAndSourceInspector() {
        continueAfterFailure = false
        let app = DenseCodeCityJourney.openDenseInspector(in: self)
        app.buttons["Close code towers"].tap()
        XCTAssertTrue(app.navigationBars["Health"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Current · partial report"].exists)
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
