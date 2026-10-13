import XCTest
import SwiftUI
import SceneKit
@testable import GrantTap

@MainActor
final class ProjectTowerLiveMapTests: XCTestCase {
    private final class ReceivedMap: ObservableObject {
        @Published var value: ProjectCodeMap
        init(_ value: ProjectCodeMap) { self.value = value }
    }
    private struct LiveView: View {
        @ObservedObject var received: ReceivedMap
        var body: some View {
            ProjectTowersFullScreen(report: ProjectTowerViewFixtures.report(),
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
}
