#if !targetEnvironment(macCatalyst)
// iOS popover automation. Native Mac system menus are verified through the CUA fixture.
import XCTest

final class TurnModelPickerUITests: XCTestCase {
    func testModelDescriptionsAndContextConfirmationPreserveCanceledChoice() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_OPEN_SESSION": "1",
            "GRANTTAP_TEST_MODELS": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        app.activate()
        let picker = app.buttons["composer.model"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
        XCTAssertTrue(picker.label.contains("GPT-6 Sol"))
        picker.activatePickerControl()
        let astra = app.buttons["composer.model.select.gpt-6-astra"]
        XCTAssertTrue(astra.waitForExistence(timeout: 5))
        XCTAssertTrue(astra.label.contains("Frontier intelligence"))
        let effort = app.descendants(matching: .any).matching(identifier: "composer.effort").firstMatch
        XCTAssertTrue(effort.exists)
        effort.activatePickerControl()
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "composer.effort.select.high", "High"))
            .firstMatch.activatePickerControl()
        XCTAssertTrue(effort.label.contains("High"))
        capture(app, name: "Provider model and effort")
        astra.activatePickerControl()
        let warning = app.alerts["Switch model?"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        XCTAssertTrue(warning.staticTexts.containing(NSPredicate(format: "label CONTAINS 'context will be reloaded'")).firstMatch.exists)
        capture(app, name: "Model switch context confirmation")
        warning.buttons["Cancel"].activatePickerControl()
        XCTAssertTrue(astra.waitForExistence(timeout: 5))
        app.buttons["Done"].activatePickerControl()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.label.contains("GPT-6 Sol"))
        picker.activatePickerControl()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "composer.effort").firstMatch.label.contains("High"), "Effort must survive reopening the picker.")
        astra.activatePickerControl()
        warning.buttons["Switch model"].activatePickerControl()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.label.contains("GPT-6 Astra"))
        picker.activatePickerControl()
        app.buttons["composer.model.current"].activatePickerControl()
        XCTAssertTrue(warning.waitForExistence(timeout: 5), "returning to Sol also reloads context")
        warning.buttons["Switch model"].activatePickerControl()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.label.contains("GPT-6 Sol"))
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}

private extension XCUIElement {
    func activatePickerControl() {
        #if targetEnvironment(macCatalyst)
        click()
        #else
        tap()
        #endif
    }
}

#endif
