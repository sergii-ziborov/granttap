#if targetEnvironment(macCatalyst)
import XCTest

/// Capture the native demo without exposing the owner's tasks or credentials.
final class MacReleaseCaptureUITests: XCTestCase {
    func testCurrentNativeMacScreensInBothStoreLanguages() {
        continueAfterFailure = false
        for language in ["en", "ru"] {
            for (name, tab) in [("01-now", "now"), ("02-tasks", "tasks"),
                                ("03-task", "tasks"), ("04-usage", "usage"),
                                ("05-projects", "projects")] {
                let app = XCUIApplication()
                app.launchEnvironment = ["GRANTTAP_DEMO": "1",
                    "GRANTTAP_TEST_LANGUAGE": language, "GRANTTAP_TAB": tab,
                    "GRANTTAP_CAPTURE_TASKS": name == "02-tasks" ? "1" : "0"]
                app.launch()
                app.activate()
                XCTAssertTrue(app.buttons["sidebar.\(tab)"].waitForExistence(timeout: 20))
                if name == "03-task" {
                    let chat = app.buttons["task.task:granttap-project-demo\u{1f}granttap-release-task-demo"]
                    XCTAssertTrue(chat.waitForExistence(timeout: 10))
                    chat.click()
                    XCTAssertTrue(app.buttons["chat.open-mesh"].waitForExistence(timeout: 10))
                }
                let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                image.name = "Mac-\(language)-\(name)"
                image.lifetime = .keepAlways
                add(image)
                app.terminate()
            }
        }
    }
}
#endif
