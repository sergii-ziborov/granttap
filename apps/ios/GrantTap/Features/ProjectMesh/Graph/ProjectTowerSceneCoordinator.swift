import SceneKit
import SwiftUI
import simd

extension ProjectTowerScene {
    @MainActor final class Coordinator: NSObject, SCNCameraControllerDelegate {
        var parent: ProjectTowerScene
        weak var view: SCNView?
        private var snapshot: ProjectTowerSnapshot?
        private var renderTask: Task<Void, Never>?
        private var selection = ""
        private var lastCommand: UUID?

        init(parent: ProjectTowerScene) { self.parent = parent }

        var pose: ProjectTowerCameraPose? {
            guard let view, let camera = view.pointOfView else { return nil }
            let target = view.defaultCameraController.target
            return ProjectTowerCameraPose(position: camera.simdPosition,
                target: SIMD3(target.x, target.y, target.z))
        }

        func replaceScene() {
            guard let view else { return }
            let previous = pose
            view.scene = ProjectTowerSceneBuilder.scene(for: parent.snapshot)
            view.pointOfView = view.scene?.rootNode.childNode(withName: "tower-camera", recursively: false)
            view.defaultCameraController.pointOfView = view.pointOfView
            snapshot = parent.snapshot
            move(to: previous ?? overview(), animated: false)
        }

        func update() {
            guard let view else { return }
            if snapshot != parent.snapshot { replaceScene() }
            view.defaultCameraController.interactionMode = parent.settings.navigation == .orbit ? .orbitTurntable : .pan
            ProjectTowerHighlighting.apply(parent.snapshot, to: view.scene,
                path: parent.selectedPath, symbol: parent.selectedSymbol, settings: parent.settings)
            let next = "\(parent.selectedPath ?? "")\u{0}\(parent.selectedSymbol ?? "")"
            if next != selection {
                selection = next
                if parent.settings.autoFocus { focus() }
            }
            if let command = parent.command, lastCommand != command.id {
                lastCommand = command.id
                apply(command.action)
            }
            updateAccessibility()
            keepRendering()
        }

        func apply(_ action: ProjectTowerCameraAction) {
            guard let pose else { return }
            switch action {
            case .zoomIn: move(to: pose.zoomed(0.8))
            case .zoomOut: move(to: pose.zoomed(1.25))
            case .fit, .isometric: move(to: overview())
            case .top: move(to: overview(top: true))
            case .focus: focus()
            case .orbitLeft: move(to: pose.orbited(-.pi / 12))
            case .orbitRight: move(to: pose.orbited(.pi / 12))
            }
        }

        private func overview(top: Bool = false) -> ProjectTowerCameraPose {
            let size = view?.bounds.size ?? .zero
            return .overview(parent.snapshot, aspect: Float(size.width / max(1, size.height)), top: top)
        }

        private func focus() {
            guard let tower = parent.snapshot.towers.first(where: { $0.id == parent.selectedPath }) else { return }
            move(to: .focus(tower, symbolId: parent.selectedSymbol))
        }

        private func move(to pose: ProjectTowerCameraPose, animated: Bool = true) {
            guard let view, let camera = view.pointOfView else { return }
            view.defaultCameraController.stopInertia()
            SCNTransaction.begin()
            SCNTransaction.animationDuration = animated && !UIAccessibility.isReduceMotionEnabled ? 0.65 : 0
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            camera.simdPosition = pose.position
            let target = SCNVector3(pose.target.x, pose.target.y, pose.target.z)
            camera.look(at: target)
            view.defaultCameraController.target = target
            SCNTransaction.commit()
            updateAccessibility()
            keepRendering()
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view, let hit = view.hitTest(gesture.location(in: view), options: [
                .categoryBitMask: 1, .searchMode: SCNHitTestSearchMode.closest.rawValue,
            ]).first, let name = hit.node.name, name.hasPrefix("tower:") else { return }
            let path = String(name.dropFirst("tower:".count))
            guard let tower = parent.snapshot.towers.first(where: { $0.id == path }) else { return }
            parent.selectedPath = path
            let symbol = ProjectTowerSectionGeometry.hit(tower, height: hit.localCoordinates.y)
            parent.selectedSymbol = symbol == path ? nil : symbol
            keepRendering()
        }

        @objc func cameraGesture(_ gesture: UIGestureRecognizer) { keepRendering() }

        nonisolated func cameraInertiaWillStart(for cameraController: SCNCameraController) {
            Task { @MainActor [weak self] in self?.keepRendering() }
        }
        nonisolated func cameraInertiaDidEnd(for cameraController: SCNCameraController) {
            Task { @MainActor [weak self] in self?.keepRendering() }
        }

        func keepRendering() {
            guard let view else { return }
            renderTask?.cancel()
            view.isPlaying = true
            view.rendersContinuously = true
            view.setNeedsDisplay()
            renderTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard !Task.isCancelled, let self, let view = self.view else { return }
                if view.defaultCameraController.isInertiaRunning { self.keepRendering(); return }
                view.rendersContinuously = false
                view.isPlaying = false
                self.updateAccessibility()
            }
        }

        private func updateAccessibility() {
            guard let view, let pose else { return }
            view.accessibilityValue = String(format: "%.1f · %.1f, %.1f, %.1f",
                simd_length(pose.position - pose.target), pose.target.x, pose.target.y, pose.target.z)
        }

        func stop() {
            renderTask?.cancel()
            view?.isPlaying = false
            view?.rendersContinuously = false
        }
    }
}
