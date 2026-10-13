import XCTest
import UIKit

final class ProjectArchitectureInfoUITests: XCTestCase {
    func testGraphExplainsItsScopeAndNavigatesComponentRelations() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_CAPTURE_TAB": "projects",
                                 "GRANTTAP_TEST_GRAPH": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        let project = app.buttons["projects.row.granttap-project-demo"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        app.buttons["project.openGraph"].tap()
        let open = app.buttons["architecture.fullscreen.github.com/sergii-ziborov/granttap"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let info = app.buttons["architecture.info"]
        XCTAssertTrue(info.waitForExistence(timeout: 10))
        let graphVisible = graphIsVisible(app)
        capture(app, "Architecture graph overview")
        XCTAssertTrue(graphVisible, "The graph must draw coloured components before inspection")
        info.tap()
        XCTAssertTrue(app.staticTexts["How to read this graph"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["demo-revision"].exists)
        capture(app, "Architecture report information")
        app.buttons["Done"].tap()
        app.buttons["architecture.components"].tap()
        let watch = app.buttons["architecture.component.watch"]
        XCTAssertTrue(watch.waitForExistence(timeout: 5))
        watch.tap()
        XCTAssertTrue(app.staticTexts["Component relations"].waitForExistence(timeout: 5))
        capture(app, "Architecture component details")
        app.buttons["architecture.show-on-graph"].tap()
        XCTAssertTrue(app.staticTexts["architecture.inspector.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["architecture.inspector.title"].label, "Watch")
        let search = app.textFields["architecture.search"]
        search.tap()
        search.typeText("no-such-component")
        XCTAssertTrue(app.staticTexts["No matching components"].waitForExistence(timeout: 5))
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func graphIsVisible(_ app: XCUIApplication) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            guard let image = app.screenshot().image.cgImage else { return false }
            let width = image.width, height = image.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            var coloured = 0
            for y in (height / 4)..<(height * 4 / 5) {
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    let red = Int(pixels[offset]), green = Int(pixels[offset + 1]), blue = Int(pixels[offset + 2])
                    // The dark palette's green is deliberately muted. Both
                    // palettes must show a distinct green component, while
                    // neutral backgrounds and labels remain excluded.
                    if green > red + 12 && green > blue + 25 { coloured += 1 }
                }
            }
            if coloured > 100 { return true }
        } while Date() < deadline
        return false
    }
}
