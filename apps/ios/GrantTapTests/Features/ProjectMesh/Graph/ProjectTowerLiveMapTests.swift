import XCTest
import SwiftUI
import SceneKit
import WebKit
@testable import GrantTap

@MainActor
final class ProjectTowerLiveMapTests: XCTestCase {
    func testActualRepoLensSceneKeepsAllReceivedTowerCentersInTheInitialViewport() async throws {
        let map = ProjectTowerViewFixtures.largeMap()
        let report = ProjectRepositoryGraph(projectId: UUID().uuidString, repositoryId: "portable-repository",
            revision: "fresh-source", weavatrixVersion: "2.17.4", analysisStatus: "COMPLETE",
            nodes: [], relations: [], totalNodes: 0, totalRelations: 0, truncated: false)
        let controller = UIHostingController(rootView: ProjectTowersFullScreen(
            report: report, repositoryName: "Portable workspace", map: map))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 900))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        let web = try XCTUnwrap(webView(in: controller.view))
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript("typeof window.graphViewSnapshot === 'function'")) as? Bool == true { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        _ = try await web.evaluateJavaScript("[...document.querySelectorAll('.graph-camera button')].find(b => b.textContent === 'Fit').click()")
        try await Task.sleep(nanoseconds: 400_000_000)
        let frame = try await web.evaluateJavaScript("window.graphViewSnapshot()") as? [String: Any]
        let towers = try XCTUnwrap(frame?["towers"] as? [[String: Any]])
        let density = try XCTUnwrap(frame?["fogDensity"] as? Double)
        XCTAssertEqual(towers.count, 650)
        for tower in towers {
            let point = try XCTUnwrap(tower["projected"] as? [Double])
            XCTAssertTrue(point.allSatisfy { $0.isFinite && abs($0) <= 1 }, String(describing: frame))
            let distance = try XCTUnwrap(tower["distance"] as? Double)
            XCTAssertGreaterThan(exp(-pow(density * distance, 2)), 0.5)
        }
    }

    func testReceivedFileSelectionOpensTheActualSourceInspector() async throws {
        let map = ProjectTowerViewFixtures.map()
        let controller = UIHostingController(rootView: ProjectTowersFullScreen(
            report: ProjectTowerViewFixtures.report(), repositoryName: "Portable workspace", map: map))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 900))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        let web = try XCTUnwrap(webView(in: controller.view))
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript("Boolean(document.querySelector('.graph-camera'))")) as? Bool == true { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let result = try await web.evaluateJavaScript("""
            (() => {
              [...document.querySelectorAll('.graph-tools button')].find(b => b.textContent === 'Files').click();
              const source = [...document.querySelectorAll('.graph-browser details button')]
                .find(b => b.textContent === 'Sources/Example.swift');
              source.click();
              return { browserClosed: document.querySelector('.graph-browser').hidden,
                inspectorVisible: !document.querySelector('.granttap-inspector').hidden,
                path: document.querySelector('.granttap-inspector > p')?.textContent,
                error: window.graphLoadError || '' };
            })()
            """) as? [String: Any]
        XCTAssertEqual(result?["browserClosed"] as? Bool, true, String(describing: result))
        XCTAssertEqual(result?["inspectorVisible"] as? Bool, true)
        XCTAssertEqual(result?["path"] as? String, ProjectTowerViewFixtures.path)
        _ = try await web.evaluateJavaScript("document.querySelector('[data-section-index=\"35\"]').click()")
        try await Task.sleep(nanoseconds: 700_000_000)
        let receivesTouch = try await web.evaluateJavaScript("""
            (() => {
              const tab = [...document.querySelectorAll('.granttap-inspector nav button')]
                .find(b => b.textContent === 'Links');
              let received = false;
              tab.addEventListener('pointerdown', () => { received = true; }, { once: true });
              tab.dispatchEvent(new PointerEvent('pointerdown', {
                bubbles: true, pointerType: 'touch', pointerId: 7, clientX: 200, clientY: 400
              }));
              tab.dispatchEvent(new PointerEvent('pointercancel', { bubbles: true, pointerId: 7 }));
              return received;
            })()
            """) as? Bool
        XCTAssertEqual(receivesTouch, true, "The tower's touch rail must not capture inspector controls")
    }

    func testAnUnchangedReceivedReportKeepsTheOpenSourceSearch() async throws {
        let map = ProjectTowerViewFixtures.map()
        var report = ProjectTowerViewFixtures.report()
        report.codeMap = map
        let controller = UIHostingController(rootView: ProjectTowersFullScreen(
            report: report, repositoryName: "Portable workspace", map: map))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 900))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        let web = try XCTUnwrap(webView(in: controller.view))
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript("Boolean(document.querySelector('.graph-camera'))")) as? Bool == true { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let bridge = MeshCyberboardView(reports: [report], failed: .constant(false)).makeCoordinator()
        bridge.deliver(to: web)
        try await Task.sleep(nanoseconds: 200_000_000)
        _ = try await web.evaluateJavaScript("""
            [...document.querySelectorAll('.graph-tools button')].find(b => b.textContent === 'Files').click();
            document.querySelector('.graph-browser input').value = 'retained source search';
            """)
        for _ in 0..<8 {
            bridge.deliver(to: web)
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let query = try await web.evaluateJavaScript("document.querySelector('.graph-browser input').value") as? String
        XCTAssertEqual(query, "retained source search", "Repeated equal reports must not restart the viewer")
    }

    func testPhoneUsesTheBundledRepoLensViewerWithReceivedSourceFacts() async throws {
        let map = ProjectTowerViewFixtures.map()
        let controller = UIHostingController(rootView: ProjectTowersFullScreen(
            report: ProjectTowerViewFixtures.report(), repositoryName: "Portable workspace", map: map))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 900))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        let web = try XCTUnwrap(webView(in: controller.view), "Phone must use the same Repo Lens renderer as Mac")
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript("Boolean(document.querySelector('.graph-camera'))")) as? Bool == true { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(web.url?.isFileURL == true, "Received maps remain usable offline")
        let path = try await web.evaluateJavaScript("window.meshReports[0].codeMap.files[0].path") as? String
        XCTAssertEqual(path, ProjectTowerViewFixtures.path)
        let controls = try await web.evaluateJavaScript("Boolean(document.querySelector('.graph-camera'))") as? Bool
        let failure = try await web.evaluateJavaScript("window.graphLoadError || ''") as? String
        XCTAssertEqual(controls, true, "Repo Lens must finish loading its real controls: \(failure ?? "")")
    }

    private final class ReceivedMap: ObservableObject {
        @Published var value: ProjectCodeMap
        init(_ value: ProjectCodeMap) { self.value = value }
    }
    private struct LiveView: View {
        @ObservedObject var received: ReceivedMap
        var body: some View {
            ProjectNativeTowersView(report: ProjectTowerViewFixtures.report(),
                repositoryName: "Live report", map: received.value)
        }
    }

    func testAReceivedReportUpdatesAnAlreadyOpenSceneWithoutResettingTheCamera() throws {
        let initial = map(["first.swift"]), received = ReceivedMap(initial)
        let controller = UIHostingController(rootView: LiveView(received: received))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 900))
        window.rootViewController = controller; window.isHidden = false
        defer { window.isHidden = true }
        controller.view.frame = window.bounds; settle(controller.view)
        let scene = try XCTUnwrap(sceneView(in: controller.view))
        XCTAssertNotNil(scene.scene?.rootNode.childNode(withName: "tower:first.swift", recursively: false))
        let camera = try XCTUnwrap(scene.pointOfView)
        let before = camera.simdPosition
        received.value = map(["first.swift", "second.swift"]); settle(controller.view)
        XCTAssertNotNil(scene.scene?.rootNode.childNode(withName: "tower:second.swift", recursively: false))
        XCTAssertEqual(scene.pointOfView?.simdPosition, before)
        received.value = map(["second.swift"]); settle(controller.view)
        XCTAssertNil(scene.scene?.rootNode.childNode(withName: "tower:first.swift", recursively: false))
    }

    private func map(_ paths: [String]) -> ProjectCodeMap {
        ProjectCodeMap(files: paths.map { .init(path: $0, language: "swift", lineCount: 20,
            symbols: [.init(id: $0, label: "function", kind: "function", startLine: 1, lineCount: 20)]) },
            roads: [], totalFiles: paths.count, truncated: false)
    }

    private func settle(_ view: UIView) {
        view.setNeedsLayout(); view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25)); view.layoutIfNeeded()
    }

    private func sceneView(in view: UIView) -> SCNView? {
        if let scene = view as? SCNView { return scene }
        return view.subviews.lazy.compactMap { self.sceneView(in: $0) }.first
    }

    private func webView(in view: UIView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        return view.subviews.lazy.compactMap { self.webView(in: $0) }.first
    }
}
