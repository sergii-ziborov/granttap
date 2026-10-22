import XCTest

/// Drives the public review entry, without the automatic DEBUG demo fixtures.
final class AppReviewJourneyUITests: XCTestCase {
    func testPublicDemoResolvesASampleDecisionAndReturnsToConnection() {
        continueAfterFailure = false
        let app = launchDemo(language: "en")
        let request = app.buttons["approval.details.demo-approval"]
        XCTAssertTrue(request.waitForExistence(timeout: 10))
        press(app.buttons["Deny"].firstMatch)
        XCTAssertFalse(request.exists)
        #if targetEnvironment(macCatalyst)
        press(app.buttons["sidebar.settings"])
        #else
        press(app.buttons["Settings"])
        #endif
        let exit = app.buttons["Exit Demo"]
        for _ in 0..<8 where !exit.isHittable { app.swipeUp() }
        XCTAssertTrue(exit.isHittable)
        press(exit)
        XCTAssertTrue(app.buttons["demo.start"].waitForExistence(timeout: 10))
        app.terminate()
    }

    func testCurrentScreensInEnglishAndRussianThroughThePublicDemo() {
        continueAfterFailure = false
        for language in ["en", "ru"] {
            for screen in ["now", "tasks", "task", "usage", "projects"] {
                let app = launchDemo(language: language)
                if screen != "now" { select(screen == "task" ? "tasks" : screen, in: app, language: language) }
                if screen == "task" {
                    let task = app.buttons["task.task:granttap-project-demo\u{1f}granttap-release-task-demo"]
                    XCTAssertTrue(task.waitForExistence(timeout: 10))
                    press(task)
                    XCTAssertTrue(app.descendants(matching: .any)["chat.transcript"].firstMatch
                        .waitForExistence(timeout: 10))
                }
                if screen == "projects" {
                    let project = app.descendants(matching: .any)["projects.row.granttap-project-demo"].firstMatch
                    XCTAssertTrue(project.waitForExistence(timeout: 10))
                    press(project)
                    XCTAssertTrue(app.buttons["project.new-task"].waitForExistence(timeout: 10))
                }
                #if targetEnvironment(macCatalyst)
                let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                #else
                let image = XCTAttachment(screenshot: app.screenshot())
                #endif
                image.name = "AppReview-\(language)-\(screen)"
                image.lifetime = .keepAlways
                add(image)
                app.terminate()
            }
        }
    }

    private func launchDemo(language: String) -> XCUIApplication {
        let app = XCUIApplication()
        #if targetEnvironment(macCatalyst)
        // No service is contacted on the build host during the clean-review journey.
        app.launchEnvironment = ["GRANTTAP_MCP_HTTP_PORT": "0"]
        #endif
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale",
            language == "ru" ? "ru_RU" : "en_US", "-granttap.language", language]
        app.launch()
        app.activate()
        let start = app.buttons["demo.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        press(start)
        XCTAssertTrue(app.buttons["approval.details.demo-approval"].waitForExistence(timeout: 10))
        #if targetEnvironment(macCatalyst)
        XCTAssertTrue(app.descendants(matching: .any)["mac.brand-header"].firstMatch.label
            .contains(language == "ru" ? "Демо" : "Demo"))
        #endif
        return app
    }

    private func select(_ tab: String, in app: XCUIApplication, language: String) {
        #if targetEnvironment(macCatalyst)
        press(app.buttons["sidebar.\(tab)"])
        #else
        let labels = language == "ru"
            ? ["tasks": "Задачи", "usage": "Расход", "projects": "Mesh"]
            : ["tasks": "Tasks", "usage": "Usage", "projects": "Mesh"]
        let control = app.descendants(matching: .any)[labels[tab]!].firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 10))
        press(control)
        #endif
    }

    private func press(_ element: XCUIElement) {
        #if targetEnvironment(macCatalyst)
        element.click()
        #else
        element.tap()
        #endif
    }
}
