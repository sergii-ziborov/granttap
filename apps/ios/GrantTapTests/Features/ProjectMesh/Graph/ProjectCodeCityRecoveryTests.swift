import XCTest
import SwiftUI
import SceneKit
import WebKit
@testable import GrantTap

@MainActor
final class ProjectCodeCityRecoveryTests: XCTestCase {
    func testRendererFailureKeepsReceivedSourceAvailableInTheNativeFallback() async throws {
        setenv("GRANTTAP_TEST_GRAPH_RENDER_FAILURE", "1", 1)
        defer { unsetenv("GRANTTAP_TEST_GRAPH_RENDER_FAILURE") }
        let controller = UIHostingController(rootView: ProjectTowersFullScreen(
            report: ProjectTowerViewFixtures.report(), repositoryName: "Portable workspace",
            map: ProjectTowerViewFixtures.map()))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 900))
        window.rootViewController = controller; window.isHidden = false
        defer { window.isHidden = true }
        controller.view.frame = window.bounds; controller.view.layoutIfNeeded()
        for _ in 0..<50 {
            controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
            if scene(in: controller.view) != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let web = web(in: controller.view)
        let error = try? await web?.evaluateJavaScript("window.graphLoadError || ''")
        let view = try XCTUnwrap(scene(in: controller.view),
            "Flag: \(ProcessInfo.processInfo.environment["GRANTTAP_TEST_GRAPH_RENDER_FAILURE"] ?? "unset"); scripts: \(web?.configuration.userContentController.userScripts.count ?? -1); error: \(String(describing: error))")
        XCTAssertNotNil(view.scene?.rootNode.childNode(withName: "tower:Sources/Example.swift", recursively: false))
        XCTAssertNotNil(view.scene?.rootNode.childNode(withName: "tower:README.md", recursively: false))
    }

    private func scene(in view: UIView) -> SCNView? {
        if let value = view as? SCNView { return value }
        return view.subviews.lazy.compactMap { self.scene(in: $0) }.first
    }

    private func web(in view: UIView) -> WKWebView? {
        if let value = view as? WKWebView { return value }
        return view.subviews.lazy.compactMap { self.web(in: $0) }.first
    }
}
