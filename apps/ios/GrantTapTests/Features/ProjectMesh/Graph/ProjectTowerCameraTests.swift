import XCTest
import SceneKit
import SwiftUI
import simd
@testable import GrantTap

@MainActor
final class ProjectTowerCameraTests: XCTestCase {
    private var snapshot: ProjectTowerSnapshot {
        ProjectTowerLayout.build(ProjectCodeMap(files: [
            .init(path: "src/main.swift", language: "swift", lineCount: 80, symbols: [
                .init(id: "first", label: "first()", kind: "function", startLine: 1, lineCount: 20),
                .init(id: "last", label: "last()", kind: "function", startLine: 30, lineCount: 40),
            ]), .init(path: "src/store.swift", language: "swift", lineCount: 50, symbols: []),
        ], roads: [.init(source: "src/main.swift", target: "src/store.swift", relation: "calls")],
           totalFiles: 2, truncated: false))
    }

    func testSectionPickingUsesMeasuredRangesAndPreservesIdentityThroughGaps() throws {
        let tower = try XCTUnwrap(snapshot.towers.first { $0.id == "src/main.swift" })
        let last = try XCTUnwrap(ProjectTowerSectionGeometry.section(tower, id: "last"))
        XCTAssertEqual(ProjectTowerSectionGeometry.hit(tower, height: last.center), "last")
        XCTAssertNil(ProjectTowerSectionGeometry.hit(tower, height: -1))
        XCTAssertNil(ProjectTowerSectionGeometry.hit(tower, height: tower.segments[0].height + 0.2))
        XCTAssertNil(ProjectTowerSectionGeometry.section(tower, id: "missing"))
        let focus = ProjectTowerCameraPose.focus(tower, symbolId: "last")
        XCTAssertEqual(focus.target.y, last.center)
        XCTAssertEqual(focus.target.x, tower.x)
    }

    func testZoomAndOrbitRetainTargetAndBoundDistance() {
        let initial = ProjectTowerCameraPose(position: SIMD3(12, 20, 100), target: SIMD3(2, 3, 4))
        XCTAssertEqual(initial.zoomed(0.5).target, initial.target)
        XCTAssertEqual(simd_distance(initial.zoomed(0.5).position, initial.target),
                       simd_distance(initial.position, initial.target) / 2, accuracy: 0.001)
        XCTAssertEqual(simd_distance(initial.zoomed(0.0001).position, initial.target), 8, accuracy: 0.001)
        XCTAssertEqual(initial.zoomed(.nan), initial)
        XCTAssertEqual(initial.zoomed(0), initial)
        let empty = ProjectTowerCameraPose(position: .zero, target: .zero)
        XCTAssertEqual(empty.zoomed(0.5), empty)
        XCTAssertEqual(initial.orbited(.pi).target, initial.target)
        XCTAssertEqual(simd_distance(initial.orbited(.pi).position, initial.target),
                       simd_distance(initial.position, initial.target), accuracy: 0.001)
        let top = ProjectTowerCameraPose.overview(snapshot, aspect: 2, top: true)
        XCTAssertEqual(top.position.x, top.target.x)
        XCTAssertGreaterThan(top.position.y, top.target.y)
    }

    func testCommandsMoveTheSceneCameraAndColourRefreshRetainsTheView() throws {
        let view = SCNView(frame: CGRect(x: 0, y: 0, width: 640, height: 480))
        let scene = ProjectTowerScene(snapshot: snapshot, selectedPath: .constant(nil))
        let coordinator = scene.makeCoordinator()
        coordinator.view = view
        defer { coordinator.stop() }
        coordinator.replaceScene()
        let before = try XCTUnwrap(coordinator.pose)
        coordinator.apply(.zoomIn)
        XCTAssertLessThan(simd_distance(try XCTUnwrap(coordinator.pose).position, before.target),
                          simd_distance(before.position, before.target))
        coordinator.apply(.zoomOut)
        for action in [ProjectTowerCameraAction.top, .isometric, .orbitLeft, .orbitRight, .fit] {
            coordinator.apply(action)
            XCTAssertTrue(try XCTUnwrap(coordinator.pose).position.x.isFinite)
        }
        coordinator.parent = ProjectTowerScene(snapshot: snapshot, selectedPath: .constant("src/main.swift"),
                                               selectedSymbol: .constant("last"))
        coordinator.update()
        coordinator.apply(.focus)
        let selectedPose = try XCTUnwrap(coordinator.pose)
        XCTAssertEqual(view.defaultCameraController.target.y, selectedPose.target.y)
        XCTAssertNotNil(view.scene?.rootNode.childNode(withName: "selected-section", recursively: true))
        var settings = ProjectTowerViewSettings()
        settings.navigation = .pan; settings.autoFocus = false; settings.highlight = .all
        settings.roads = false; settings.labels = false
        coordinator.parent = ProjectTowerScene(snapshot: snapshot, selectedPath: .constant("src/store.swift"),
            command: ProjectTowerCameraRequest(action: .zoomIn), settings: settings)
        coordinator.update()
        XCTAssertEqual(view.defaultCameraController.interactionMode, .pan)
        let pose = try XCTUnwrap(coordinator.pose)
        coordinator.replaceScene()
        XCTAssertEqual(coordinator.pose, pose)
        XCTAssertFalse(view.accessibilityValue?.isEmpty ?? true)
    }

    func testSceneReturnsToIdleAfterCameraInteractionStops() async throws {
        let view = SCNView()
        let coordinator = ProjectTowerScene(snapshot: snapshot, selectedPath: .constant(nil)).makeCoordinator()
        coordinator.view = view
        defer { coordinator.stop() }
        coordinator.replaceScene()
        coordinator.keepRendering()
        XCTAssertTrue(view.rendersContinuously)
        try await Task.sleep(nanoseconds: 1_100_000_000)
        XCTAssertFalse(view.rendersContinuously)
        XCTAssertFalse(view.isPlaying)
    }
}
