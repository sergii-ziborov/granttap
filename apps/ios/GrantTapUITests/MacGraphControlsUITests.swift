#if targetEnvironment(macCatalyst)
import XCTest

final class MacGraphControlsUITests: XCTestCase {
    func testCodeCitySectionsHealthAndFullScreenRemainInteractive() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_TAB": "projects",
            "GRANTTAP_TEST_TOWER_SECTIONS": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch(); app.activate()
        let project = app.buttons["projects.row.granttap-project-demo"]
        XCTAssertTrue(project.waitForExistence(timeout: 15)); project.click()
        let graph = app.buttons["project.openGraph"]
        XCTAssertTrue(graph.waitForExistence(timeout: 5)); graph.click()
        app.buttons["Code city"].click()
        let files = app.webViews.buttons["Files"].firstMatch
        XCTAssertTrue(files.waitForExistence(timeout: 15)); files.click()
        let search = app.webViews.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.click(); search.typeText("healthSection36")
        let last = app.webViews.buttons["healthSection36 · L360"]
        XCTAssertTrue(last.waitForExistence(timeout: 5)); last.click()
        XCTAssertTrue(app.webViews.staticTexts["Observed source"].exists)
        CodeCityJourney.control("Health", in: app).click()
        XCTAssertTrue(app.webViews.staticTexts["Health evidence"].exists)
        let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        image.name = "Mac code city with measured tower health evidence"
        image.lifetime = .keepAlways; add(image)
        app.webViews.buttons["Full screen"].firstMatch.click()
        XCTAssertTrue(app.buttons["Exit full screen"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.webViews.staticTexts["Health evidence"].waitForExistence(timeout: 8))
        app.buttons["Exit full screen"].click()
        XCTAssertTrue(app.webViews.buttons["Files"].firstMatch.waitForExistence(timeout: 8))
        app.terminate()
    }
}
#endif
