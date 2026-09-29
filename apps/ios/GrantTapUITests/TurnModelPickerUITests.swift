import XCTest

final class TurnModelPickerUITests: XCTestCase {
    func testModelDescriptionsAndContextConfirmationPreserveCanceledChoice() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_OPEN_SESSION": "1",
            "GRANTTAP_TEST_MODELS": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let picker = app.buttons["composer.model"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
        XCTAssertTrue(picker.label.contains("GPT-6 Sol"))
        picker.tap()
        let astra = app.buttons["composer.model.select.gpt-6-astra"]
        XCTAssertTrue(astra.waitForExistence(timeout: 5))
        XCTAssertTrue(astra.label.contains("Frontier intelligence"))
        XCTAssertTrue(app.buttons["composer.model.select.gpt-6-luna"].label.contains("Fast and affordable"))
        capture(app, name: "Provider model descriptions")
        astra.tap()
        let warning = app.alerts["Switch model?"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        XCTAssertTrue(warning.staticTexts.containing(NSPredicate(format: "label CONTAINS 'context will be reloaded'")).firstMatch.exists)
        capture(app, name: "Model switch context confirmation")
        warning.buttons["Cancel"].tap()
        XCTAssertTrue(astra.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.label.contains("GPT-6 Sol"))
        picker.tap()
        astra.tap()
        warning.buttons["Switch model"].tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.label.contains("GPT-6 Astra"))
        picker.tap()
        app.buttons["composer.model.current"].tap()
        XCTAssertTrue(warning.waitForExistence(timeout: 5), "returning to Sol also reloads context")
        warning.buttons["Switch model"].tap()
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
