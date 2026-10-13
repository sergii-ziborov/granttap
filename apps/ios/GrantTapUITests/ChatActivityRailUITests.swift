import XCTest

final class ChatActivityRailUITests: XCTestCase {
    func testReplyRailCountsOnlyCurrentRecordedChangesAndOpensModifiedDiffs() {
        let app = launch()
        let files = app.buttons["chat.work.files"]
        XCTAssertTrue(files.isEnabled)
        XCTAssertTrue(files.label.contains("4 files"), files.label)
        XCTAssertTrue(files.label.contains("247"), files.label)
        XCTAssertTrue(files.label.contains("108"), files.label)
        capture(app, "Chat work summary")
        press(files)
        XCTAssertTrue(app.segmentedControls["chat.files.mode"].waitForExistence(timeout: 5))
        let graph = app.buttons["chat.files.modified.Sources/GraphView.swift"]
        XCTAssertTrue(graph.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["chat.files.modified.old-file.swift"].exists)
        capture(app, "Current reply modified files")
        press(graph)
        XCTAssertTrue(app.staticTexts["+new value 1"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["chat.review.path"].label, "Sources/GraphView.swift")
        capture(app, "Modified file diff")
    }

    func testCachedWorkspaceTreeExpandsAndReadsPagedFilesWhileComputerIsOffline() {
        let app = launch()
        app.buttons["chat.work.files"].tap()
        let mode = app.segmentedControls["chat.files.mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        mode.buttons["All files"].tap()
        let sources = app.buttons["chat.files.workspace.Sources"]
        XCTAssertTrue(sources.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["This folder list is partial."].exists)
        XCTAssertTrue(app.navigationBars["Files"].buttons["Done"].isHittable)
        capture(app, "Cached workspace root")
        app.buttons["chat.files.load-more."].tap()
        XCTAssertTrue(app.buttons["chat.files.workspace.LICENSE"].waitForExistence(timeout: 5))
        sources.tap()
        let graph = app.buttons["chat.files.workspace.Sources/GraphView.swift"]
        XCTAssertTrue(graph.waitForExistence(timeout: 5))
        capture(app, "Expanded workspace folder")
        graph.tap()
        XCTAssertTrue(app.staticTexts["chat.files.preview.text"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["chat.files.preview.text"].label.contains("let phase = \"ready\""))
        XCTAssertTrue(app.staticTexts["Partial file preview"].exists)
        app.buttons["chat.files.preview.more"].tap()
        let text = app.staticTexts["chat.files.preview.text"]
        let loaded = NSPredicate(format: "label CONTAINS %@", "cached remainder")
        expectation(for: loaded, evaluatedWith: text)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.staticTexts["Partial file preview"].exists)
        capture(app, "Cached workspace file")
        app.navigationBars["GraphView.swift"].buttons["Done"].tap()
        XCTAssertTrue(sources.waitForExistence(timeout: 5))
        app.navigationBars["Files"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["chat.work.files"].waitForExistence(timeout: 5))
    }

    func testAgentsRailOpensNestedConversationsAndTheirKnownMessages() {
        let app = launch()
        let agents = app.buttons["chat.work.agents"]
        XCTAssertTrue(agents.isEnabled)
        XCTAssertTrue(agents.label.contains("2 agents"), agents.label)
        press(agents)
        XCTAssertTrue(app.staticTexts["Agent conversations are nested executions of this Task."]
            .waitForExistence(timeout: 5))
        let conversation = app.descendants(matching: .any)
            .matching(identifier: "chat.agents.conversation.demo-agent-release").firstMatch
        XCTAssertTrue(conversation.waitForExistence(timeout: 5))
        capture(app, "Nested agent conversations")
        press(app.buttons["thread.open.demo-agent-release"])
        XCTAssertTrue(app.staticTexts["Reviewed the component connections."].waitForExistence(timeout: 5))
        capture(app, "Agent conversation messages")
    }

    func testUncachedFolderShowsAnUnavailableStateInsteadOfInventingAnEmptyFolder() {
        let app = launch()
        app.buttons["chat.work.files"].tap()
        app.segmentedControls["chat.files.mode"].buttons["All files"].tap()
        let tests = app.buttons["chat.files.workspace.Tests"]
        XCTAssertTrue(tests.waitForExistence(timeout: 5))
        tests.tap()
        XCTAssertTrue(app.staticTexts["This folder is unavailable. Connect this Task's computer and retry."]
            .waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["No files in this folder."].exists)
        capture(app, "Unavailable uncached folder")
    }

    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_OPEN_SESSION": "1",
                                 "GRANTTAP_TEST_CHAT_WORK": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        #if targetEnvironment(macCatalyst)
        app.launchEnvironment.removeValue(forKey: "GRANTTAP_OPEN_SESSION")
        app.launchEnvironment["GRANTTAP_TAB"] = "tasks"
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO"]
        #endif
        app.launch()
        #if targetEnvironment(macCatalyst)
        app.activate()
        let chat = app.buttons["task.task:granttap-project-demo\u{1f}granttap-release-task-demo"]
        XCTAssertTrue(chat.waitForExistence(timeout: 15))
        chat.click()
        #endif
        XCTAssertTrue(app.buttons["chat.work.files"].waitForExistence(timeout: 15))
        return app
    }

    private func press(_ element: XCUIElement) {
        #if targetEnvironment(macCatalyst)
        element.click()
        #else
        element.tap()
        #endif
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
