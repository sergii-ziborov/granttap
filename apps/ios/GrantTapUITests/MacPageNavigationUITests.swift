#if targetEnvironment(macCatalyst)
import XCTest
import UIKit

final class MacPageNavigationUITests: XCTestCase {
    func testSidebarHoverHighlightsWithoutChangingTheSelectedPage() throws {
        continueAfterFailure = false
        let app = demoApp(openChat: false)
        let now = app.buttons["sidebar.now"]
        let tasks = app.buttons["sidebar.tasks"]
        let outside = app.descendants(matching: .any)["mac.brand-header"].firstMatch
        let allow = app.buttons["Allow"].firstMatch
        outside.hover()
        let idle = try backgroundBrightness(tasks)
        let selected = try backgroundBrightness(now)
        let actionIdle = try backgroundBrightness(allow)

        allow.hover()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertGreaterThan(abs(try backgroundBrightness(allow) - actionIdle), 5)

        tasks.hover()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertGreaterThan(abs(try backgroundBrightness(tasks) - idle), 5)
        XCTAssertTrue(now.isSelected)
        XCTAssertFalse(tasks.isSelected)

        outside.hover()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(try backgroundBrightness(tasks), idle, accuracy: 2)
        now.hover()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertGreaterThan(abs(try backgroundBrightness(now) - selected), 5)

        tasks.click()
        let selectedTasks = expectation(for: NSPredicate(format: "isSelected == true"),
                                        evaluatedWith: tasks)
        wait(for: [selectedTasks], timeout: 3)
        XCTAssertFalse(now.isSelected)
        app.terminate()
    }

    private func backgroundBrightness(_ element: XCUIElement) throws -> Double {
        let image = try XCTUnwrap(element.screenshot().image.cgImage)
        // Sample empty padding, away from text, icon and the pointer at row center.
        let sample = try XCTUnwrap(image.cropping(to: CGRect(x: 4, y: image.height / 2 - 2,
                                                            width: 4, height: 4)))
        var pixels = [UInt8](repeating: 0, count: 4 * 4 * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: 4, height: 4,
            bitsPerComponent: 8, bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(sample, in: CGRect(x: 0, y: 0, width: 4, height: 4))
        return stride(from: 0, to: pixels.count, by: 4).reduce(0.0) {
            $0 + Double(pixels[$1]) + Double(pixels[$1 + 1]) + Double(pixels[$1 + 2])
        } / 48
    }

    func testAccountMeshOpensFromDevicesWithoutALocalComputer() {
        continueAfterFailure = false
        let app = demoApp(openChat: false)
        app.buttons["sidebar.devices"].click()
        assertCompactHeader(app)
        XCTAssertTrue(app.staticTexts["Account Mesh"].exists)
        // Preserve the Mac's existing account while checking the navigation surface.
        XCTAssertTrue(app.buttons["Sign in with passkey"].exists
                      || app.buttons["Use a different passkey"].exists)
        XCTAssertEqual(app.sheets.count, 0)
        XCTAssertTrue(app.buttons["sidebar.devices"].isSelected)
    }

    func testChatMeshOpensTheExistingMainWindowPageAndReturnsToTheList() {
        continueAfterFailure = false
        let app = demoApp(openChat: true)
        let mesh = app.buttons["chat.open-mesh"]
        XCTAssertTrue(mesh.waitForExistence(timeout: 10))
        mesh.click()
        XCTAssertTrue(app.buttons["project.new-task"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["project.knowledge"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["sidebar.projects"].isSelected)
        XCTAssertEqual(app.sheets.count, 0)
        assertCompactHeader(app)
        app.buttons["page.back"].click()
        XCTAssertTrue(app.buttons["projects.row.granttap-project-demo"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["project.new-task"].exists)
    }

    func testLogHasTheChatHeaderAndRetainsSearchAndClear() {
        continueAfterFailure = false
        let app = demoApp(openChat: false)
        app.buttons["sidebar.settings"].click()
        let log = app.buttons["settings.open-log"]
        for _ in 0..<10 where !log.isHittable { app.scroll(byDeltaX: 0, deltaY: -400) }
        XCTAssertTrue(log.waitForExistence(timeout: 10))
        log.click()
        XCTAssertTrue(app.buttons["page.back"].waitForExistence(timeout: 10))
        assertCompactHeader(app)
        XCTAssertTrue(app.textFields["audit.search"].exists)
        XCTAssertTrue(app.buttons["Clear"].exists)
        app.buttons["page.back"].click()
        XCTAssertTrue(app.buttons["sidebar.settings"].isSelected)
    }

    private func demoApp(openChat: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["GRANTTAP_DEMO": "1", "GRANTTAP_TEST_LANGUAGE": "en"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.buttons["sidebar.settings"].waitForExistence(timeout: 10))
        if openChat {
            app.buttons["sidebar.tasks"].click()
            let chat = app.buttons["task.task:granttap-project-demo\u{1f}granttap-release-task-demo"]
            XCTAssertTrue(chat.waitForExistence(timeout: 10))
            chat.click()
        }
        return app
    }

    private func assertCompactHeader(_ app: XCUIApplication) {
        let header = app.descendants(matching: .any)["page.header"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(header.frame.height, 0)
        XCTAssertLessThanOrEqual(header.frame.height, 44)
    }
}
#endif
