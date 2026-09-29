import XCTest

final class RepositoryCatalogUITests: XCTestCase {
    func testMeshShowsRepositoryBesideChatAndOpensItsRepository() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_CAPTURE_TAB": "projects",
            "GRANTTAP_TEST_REPOSITORIES": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let mesh = app.buttons["projects.row.granttap-project-demo"]
        XCTAssertTrue(mesh.waitForExistence(timeout: 10))
        mesh.tap()
        let context = app.staticTexts["task.repository.granttap-pairing-task-demo"]
        for _ in 0..<8 where !context.isHittable { app.swipeUp() }
        XCTAssertTrue(context.exists)
        XCTAssertTrue(context.label.contains("github.com/sergii-ziborov/granttap-mcp"))
        let repository = app.buttons["project.repository.github.com/sergii-ziborov/granttap-mcp"]
        for _ in 0..<8 where !repository.isHittable { app.swipeDown() }
        XCTAssertTrue(repository.exists)
        repository.tap()
        XCTAssertTrue(app.staticTexts["repository.identity"].waitForExistence(timeout: 10))
    }

    func testRepositoryTabShowsMeshScopeAndRoutesItsChat() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_CAPTURE_TAB": "projects",
            "GRANTTAP_TEST_REPOSITORIES": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let repositories = app.segmentedControls["projects.catalog-tabs"].buttons["Repositories"]
        XCTAssertTrue(repositories.waitForExistence(timeout: 10))
        repositories.tap()
        let repo = app.buttons["repositories.row.github.com/sergii-ziborov/granttap-mcp"]
        XCTAssertTrue(repo.waitForExistence(timeout: 10))
        repo.tap()
        XCTAssertTrue(app.staticTexts["repository.identity"].waitForExistence(timeout: 10))
        let mesh = app.buttons["repository.mesh.granttap-project-demo"]
        XCTAssertTrue(mesh.exists)
        XCTAssertTrue(app.buttons["repository.mesh.granttap-runtime-demo"].exists)
        let chat = app.buttons["repository.task.granttap-project-demo.granttap-pairing-task-demo"]
        for _ in 0..<5 where !chat.isHittable { app.swipeUp() }
        XCTAssertTrue(chat.exists)
        chat.tap()
        XCTAssertTrue(app.staticTexts["Finalize the pairing API"].waitForExistence(timeout: 10))
        let openChat = app.buttons.containing(.staticText, identifier: "claude/pairing-api").firstMatch
        XCTAssertTrue(openChat.exists)
        openChat.tap()
        XCTAssertTrue(app.descendants(matching: .any)["chat.transcript"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["chat.project"].label, "granttap")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Finalize the pairing API"].waitForExistence(timeout: 10))
    }
}
