import XCTest
import SwiftUI
import WebKit
@testable import GrantTap

@MainActor
final class ProjectCodeCityInteractionTests: XCTestCase {
    func testSelectedSectionsRetainMeasuredColoursAndManualZoomInTheBundledRenderer() async throws {
        let map = receivedMap()
        let host = UIHostingController(rootView: ProjectTowersFullScreen(
            report: ProjectTowerViewFixtures.report(), repositoryName: "Portable repository", map: map))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; previousWindow?.makeKey() }
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        let web = try XCTUnwrap(findWeb(host.view))
        for _ in 0..<150 {
            if (try? await web.evaluateJavaScript("typeof window.graphViewSnapshot === 'function'")) as? Bool == true { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        _ = try await web.evaluateJavaScript("""
        window.clickGraphControl = name => {
          const button = [...document.querySelectorAll('button')].find(b => b.getAttribute('aria-label') === name || b.textContent === name);
          if (!button) throw Error('Missing control: '+name); button.click();
        };
        clickGraphControl('View settings'); clickGraphControl('Reset view settings'); clickGraphControl('Close settings');
        clickGraphControl('Files');
        [...document.querySelectorAll('.graph-browser details button')].find(b => b.textContent === 'tests/health-task.test.tsx').click();
        document.querySelector('.graph-sections button').click();
        clickGraphControl('View settings'); clickGraphControl('Code checks'); clickGraphControl('Close settings');
        clickGraphControl('Zoom in'); window.manualZoomFrame = graphViewSnapshot();
        """)
        try await Task.sleep(nanoseconds: 800_000_000)
        let checks = try await web.evaluateJavaScript("""
        (() => {
          const now = graphViewSnapshot(), before = window.manualZoomFrame;
          const stable = ['position','target'].every(key => now[key].every((n,i) => Math.abs(n-before[key][i]) < 0.001));
          const segments = now.segments.filter(s => s.fileId === 0);
          return { stable, colors: segments.filter(s => !s.sourceBody).map(s => s.color),
            maximumGlow: Math.max(...segments.map(s => s.emissiveIntensity)),
            bodyOpacity: segments.find(s => s.sourceBody).opacity,
            sourceInRail: [...document.querySelectorAll('.lbl.callout')].some(n => n.textContent.includes('Other source lines')) };
        })()
        """) as? [String: Any]
        let result = try XCTUnwrap(checks)
        XCTAssertEqual(result["stable"] as? Bool, true, "Delayed elevation must not replace manual zoom")
        XCTAssertEqual(result["colors"] as? [Int], [0x64dca6, 0xff6878])
        XCTAssertLessThanOrEqual(try XCTUnwrap(result["maximumGlow"] as? Double), 0.5)
        XCTAssertLessThanOrEqual(try XCTUnwrap(result["bodyOpacity"] as? Double), 0.58)
        XCTAssertEqual(result["sourceInRail"] as? Bool, false)
        _ = try await web.evaluateJavaScript("""
        clickGraphControl('Files');
        [...document.querySelectorAll('.graph-browser details button')].find(b => b.textContent === 'tests/health-task.test.tsx').click();
        document.querySelector('.graph-sections button').click();
        """)
        try await Task.sleep(nanoseconds: 600_000_000)
        try await capture(web, "Two measured functions and neutral source body after normal focus")
        _ = try await web.evaluateJavaScript("clickGraphControl('View settings')")
        let groups = try await web.evaluateJavaScript("[...document.querySelectorAll('.graph-view-settings fieldset>legend')].map(n=>n.textContent)") as? [String]
        XCTAssertEqual(groups, ["Colour by", "Source context", "Labels", "Links"])
        try await capture(web, "Grouped map settings on a portrait phone")
    }

    private func receivedMap() -> ProjectCodeMap {
        let symbols: [ProjectCodeMap.Symbol] = [
            .init(id: "open", label: "open", kind: "function", startLine: 14, lineCount: 5,
                  metrics: .init(measured: true, sourceLines: 5, cyclomatic: 1, maxLoopDepth: 0, callers: 1)),
            .init(id: "mesh", label: "mesh", kind: "function", startLine: 8, lineCount: 4,
                  metrics: .init(measured: true, sourceLines: 4, cyclomatic: 14, maxLoopDepth: 4, callers: 1)),
        ]
        let selected = ProjectCodeMap.File(path: "tests/health-task.test.tsx", language: "typescript",
                                           lineCount: 78, symbols: symbols)
        let surrounding = (1..<290).map { index in
            ProjectCodeMap.File(path: "Sources/Area\(index / 25)/File\(index).swift", language: "swift",
                                lineCount: 20, symbols: [])
        }
        return ProjectCodeMap(files: [selected] + surrounding, roads: [], totalFiles: 290, truncated: false)
    }

    private func findWeb(_ view: UIView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        return view.subviews.lazy.compactMap { self.findWeb($0) }.first
    }

    private func capture(_ web: WKWebView, _ name: String) async throws {
        let attachment = XCTAttachment(image: try await web.takeSnapshot(configuration: nil))
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
