import XCTest

final class ProjectTaskCreationUITests: XCTestCase {
    func testNewTaskLivesInsideMeshAndKeepsRoutingVisibleWithWorkingCancel() {
        executionTimeAllowance = 120
        continueAfterFailure = false
        let app = fixtureApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_TEST_LANGUAGE": "en",
            "GRANTTAP_TAB": "projects", "GRANTTAP_TEST_PROJECT_TASK": "1"]
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO"]
        app.launch()
        app.activate()
        #if targetEnvironment(macCatalyst)
        let newMesh = element(app, "projects.new-mesh")
        XCTAssertTrue(newMesh.waitForExistence(timeout: 15))
        XCTAssertFalse(element(app, "sidebar.new-mesh").exists)
        #endif
        press(element(app, "projects.row.granttap-project-demo"))
        let newTask = element(app, "project.new-task")
        XCTAssertTrue(newTask.waitForExistence(timeout: 10))
        #if targetEnvironment(macCatalyst)
        XCTAssertFalse(newMesh.isHittable)
        press(newTask)
        press(app.buttons["project.task.cancel"])
        waitForMesh(newTask)
        #endif
        press(newTask)
        let create = app.buttons["project.task.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        app.activate()
        let description = app.textViews["project.task.description"]
        XCTAssertTrue(description.isHittable)
        XCTAssertLessThan(description.frame.height, 260)
        XCTAssertTrue(element(app, "project.task.computer").isHittable)
        XCTAssertTrue(element(app, "project.task.workspace").isHittable)
        press(description)
        // Digits exercise real keyboard entry independently of the Mac input language.
        let draftText = "12345"
        description.typeText(draftText)
        let inputEvidence = XCTAttachment(string: description.debugDescription)
        inputEvidence.name = "Synthetic task editor after keyboard input"
        inputEvidence.lifetime = .keepAlways
        add(inputEvidence)
        XCTAssertEqual(description.value as? String, draftText, "Typing must reach the editor before changing its route.")
        #if targetEnvironment(macCatalyst)
        XCTAssertTrue(create.isHittable)
        XCTAssertLessThan(create.frame.width, 820)
        #endif
        press(element(app, "project.task.provider"))
        #if targetEnvironment(macCatalyst)
        press(app.menuItems["Grok Build"])
        #else
        press(app.buttons["Grok Build"])
        #endif
        press(element(app, "project.task.provider"))
        #if targetEnvironment(macCatalyst)
        press(app.menuItems["Codex"])
        #else
        press(app.buttons["Codex"])
        #endif
        press(element(app, "project.task.computer"))
        #if targetEnvironment(macCatalyst)
        press(app.menuItems["Workstation"])
        #else
        press(app.buttons["Workstation"])
        #endif
        press(app.buttons["composer.model"])
        XCTAssertTrue(app.buttons["composer.model.done"].waitForExistence(timeout: 5))
        press(app.buttons["composer.model.select.gpt-6-sol"])
        XCTAssertEqual(description.value as? String, draftText)
        press(app.buttons["composer.model"])
        press(app.buttons["composer.model.done"])
        XCTAssertTrue(app.buttons["project.task.cancel"].waitForExistence(timeout: 5))
        #if !targetEnvironment(macCatalyst)
        let keyboardDismissed = expectation(for: NSPredicate(format: "exists == false"),
            evaluatedWith: app.keyboards.firstMatch)
        wait(for: [keyboardDismissed], timeout: 5)
        app.swipeUp()
        #endif
        let slider = app.sliders["composer.effort.slider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: 1)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Mesh New Task with routing, model and animated effort"
        shot.lifetime = .keepAlways
        add(shot)
        press(app.buttons["project.task.cancel"])
        let discard = app.windows.buttons["Discard task"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        press(discard)
        waitForMesh(newTask)
        app.terminate()
    }

    private func fixtureApplication() -> XCUIApplication {
        if let bundle = ProcessInfo.processInfo.environment["GRANTTAP_UI_TARGET_BUNDLE_ID"] {
            return XCUIApplication(bundleIdentifier: bundle)
        }
        return XCUIApplication()
    }
    private func waitForMesh(_ newTask: XCUIElement) {
        let returned = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: newTask)
        wait(for: [returned], timeout: 5)
    }
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func press(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        #if targetEnvironment(macCatalyst)
        element.click()
        #else
        element.tap()
        #endif
    }
}
