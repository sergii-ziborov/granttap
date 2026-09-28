import SwiftUI
import SceneKit

/// Orbit, pinch and tap operate on the complete bounded Engine report.
struct ProjectArchitectureScene: UIViewRepresentable {
    let report: ProjectRepositoryGraph
    @Binding var selectedId: String?

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = UIColor(Theme.bg)
        view.scene = Self.scene(for: report)
        view.pointOfView = view.scene?.rootNode.childNode(withName: "report-camera", recursively: false)
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 30
        view.isPlaying = true
        view.rendersContinuously = true
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        context.coordinator.view = view
        context.coordinator.primeStaticFrame()
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.parent = self
        let neighborhood = Set(report.relations.filter {
            $0.source == selectedId || $0.target == selectedId
        }.flatMap { [$0.source, $0.target] }).union(selectedId.map { [$0] } ?? [])
        for node in view.scene?.rootNode.childNodes ?? [] where node.name?.hasPrefix("report:") == true {
            let id = String((node.name ?? "").dropFirst("report:".count))
            node.opacity = selectedId == nil || neighborhood.contains(id) ? 1 : 0.24
        }
        context.coordinator.focus(on: selectedId)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject {
        var parent: ProjectArchitectureScene
        weak var view: SCNView?
        private var staticFrameTask: Task<Void, Never>?
        private var focusedId: String?

        init(parent: ProjectArchitectureScene) { self.parent = parent }

        @MainActor func primeStaticFrame() {
            staticFrameTask?.cancel()
            staticFrameTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard !Task.isCancelled, let view = self?.view else { return }
                view.rendersContinuously = false
                view.isPlaying = false
                view.setNeedsDisplay()
            }
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view else { return }
            let hits = view.hitTest(gesture.location(in: view), options: [
                .searchMode: SCNHitTestSearchMode.closest.rawValue,
                .ignoreHiddenNodes: true,
            ])
            if let id = hits.compactMap({ $0.node.name }).first(where: { $0.hasPrefix("report:") }) {
                parent.selectedId = String(id.dropFirst("report:".count))
            }
        }

        func focus(on id: String?) {
            guard focusedId != id else { return }
            focusedId = id
            guard let id, let view,
                  let target = view.scene?.rootNode.childNode(withName: "report:\(id)", recursively: false)?.position,
                  let camera = view.pointOfView else { return }
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.35
            camera.position = SCNVector3(target.x, target.y, target.z + 27)
            camera.look(at: target)
            SCNTransaction.commit()
        }
    }

    static func positions(for report: ProjectRepositoryGraph) -> [String: SCNVector3] {
        ProjectArchitectureLayout.positions(for: report)
    }

    private static func scene(for report: ProjectRepositoryGraph) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor(Theme.bg)
        let positions = positions(for: report)
        let xs = positions.values.map(\.x)
        let ys = positions.values.map(\.y)
        let minX = xs.min() ?? -8
        let maxX = xs.max() ?? 8
        let minY = ys.min() ?? -8
        let maxY = ys.max() ?? 8
        let center = SCNVector3((minX + maxX) / 2, (minY + maxY) / 2, 0)
        let maxRadius = positions.values.map { sqrt($0.x * $0.x + $0.y * $0.y + $0.z * $0.z) }.max() ?? 8
        let camera = SCNNode()
        camera.name = "report-camera"
        camera.camera = SCNCamera()
        camera.camera?.zFar = 2_000
        camera.camera?.fieldOfView = 57
        camera.position = SCNVector3(center.x, center.y, max(48, maxRadius * 4.5))
        camera.look(at: center)
        scene.rootNode.addChildNode(camera)

        var vertices: [SCNVector3] = []
        for edge in report.relations {
            guard let source = positions[edge.source], let target = positions[edge.target] else { continue }
            vertices.append(source)
            vertices.append(target)
        }
        if !vertices.isEmpty {
            let source = SCNGeometrySource(vertices: vertices)
            let indices = vertices.indices.map { Int32($0) }
            let element = SCNGeometryElement(indices: indices, primitiveType: .line)
            let lines = SCNGeometry(sources: [source], elements: [element])
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(Theme.codex).withAlphaComponent(0.85)
            material.lightingModel = .constant
            lines.materials = [material]
            scene.rootNode.addChildNode(SCNNode(geometry: lines))
        }
        let degrees = report.relations.reduce(into: [String: Int]()) { result, edge in
            result[edge.source, default: 0] += 1
            result[edge.target, default: 0] += 1
        }
        let labeled = Set(report.nodes.sorted { left, right in
            let leftDegree = degrees[left.id] ?? 0
            let rightDegree = degrees[right.id] ?? 0
            return leftDegree == rightDegree ? left.id < right.id : leftDegree > rightDegree
        }.prefix(16).map(\.id))
        for node in report.nodes {
            guard let position = positions[node.id] else { continue }
            let sphere = SCNSphere(radius: node.kind == "workspace" ? 1.25 : 0.85)
            sphere.segmentCount = 12
            let material = SCNMaterial()
            material.diffuse.contents = color(for: node.kind)
            material.lightingModel = .constant
            sphere.materials = [material]
            let visual = SCNNode(geometry: sphere)
            visual.name = "report:\(node.id)"
            visual.position = position
            scene.rootNode.addChildNode(visual)
            if labeled.contains(node.id) {
                let text = String(node.label.suffix(18))
                let label = SCNText(string: text, extrusionDepth: 0)
                label.font = UIFont.systemFont(ofSize: 0.8, weight: .medium)
                label.flatness = 0.15
                label.firstMaterial?.diffuse.contents = UIColor(Theme.ink)
                label.firstMaterial?.lightingModel = .constant
                let title = SCNNode(geometry: label)
                let labelX = position.x > (minX + maxX) / 2 + (maxX - minX) * 0.25
                    ? position.x - Float(text.count) * 0.42 - 1 : position.x + 1
                title.position = SCNVector3(labelX, position.y - 0.3, position.z)
                title.constraints = [SCNBillboardConstraint()]
                scene.rootNode.addChildNode(title)
            }
        }
        return scene
    }

    private static func color(for kind: String) -> UIColor {
        switch kind {
        case "workspace": return UIColor(Theme.ok)
        case "package": return UIColor(Theme.riskMed)
        default: return UIColor(Theme.codex)
        }
    }
}
