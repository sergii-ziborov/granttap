import XCTest
import UIKit

#if !targetEnvironment(macCatalyst)
final class DuoWorkspaceUITests: XCTestCase {
    func testDraftAndSendRemainAvailableWhenTheChatRotates() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_OPEN_SESSION": "1",
                                 "GRANTTAP_TEST_LONG_TRANSCRIPT": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let composer = app.textFields["composer.message"]
        XCTAssertTrue(composer.waitForExistence(timeout: 15))
        composer.tap()
        composer.typeText("Keep this draft through rotation")
        XCTAssertTrue(app.keyboards.firstMatch.exists)

        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            let retained = NSPredicate(format: "value == %@", "Keep this draft through rotation")
            expectation(for: retained, evaluatedWith: composer)
            waitForExpectations(timeout: 5)
            XCTAssertTrue(composer.isHittable)
            XCTAssertTrue(app.buttons["composer.send"].isHittable)
            XCTAssertTrue(app.buttons["composer.send"].isEnabled)
            XCTAssertTrue(app.keyboards.firstMatch.exists)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = orientation == .portrait ? "Retained portrait draft" : "Retained landscape draft"
            shot.lifetime = .keepAlways
            add(shot)
        }
    }
}
#endif
