import SwiftUI
import SceneKit

/// Orbit, pinch and tap operate on the complete bounded Engine report.
struct ProjectArchitectureScene: UIViewRepresentable {
    let report: ProjectRepositoryGraph
    @Binding var selectedId: String?
    var viewport: CGSize = .zero

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = UIColor(Theme.bg)
        view.scene = Self.scene(for: report, viewport: viewport)
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
        view.delegate = context.coordinator
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
        context.coordinator.fit(viewport: viewport)
        context.coordinator.focus(on: selectedId)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor final class Coordinator: NSObject, SCNSceneRendererDelegate {
        var parent: ProjectArchitectureScene
        weak var view: SCNView?
        private var renderUntil: TimeInterval = 0
        private var focusedId: String?
        private var fittedSize: CGSize = .zero

        init(parent: ProjectArchitectureScene) { self.parent = parent }

        @MainActor func primeStaticFrame() {
            view?.rendersContinuously = true
            view?.isPlaying = true
            renderUntil = Date.timeIntervalSinceReferenceDate + 0.45
        }

        nonisolated func renderer(_ renderer: any SCNSceneRenderer, didRenderScene scene: SCNScene,
                                  atTime time: TimeInterval) {
            Task { @MainActor [weak self] in
                guard let self, Date.timeIntervalSinceReferenceDate >= self.renderUntil,
                      let view = self.view, view.window != nil,
                      view.bounds.width > 0, view.bounds.height > 0 else { return }
                view.rendersContinuously = false
                view.isPlaying = false
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

        func fit(viewport: CGSize, force: Bool = false) {
            guard viewport.width > 0, viewport.height > 0,
                  force || viewport != fittedSize, let view, let camera = view.pointOfView else { return }
            fittedSize = viewport
            let points = ProjectArchitectureScene.positions(for: parent.report).values.map {
                SIMD3<Float>($0.x, $0.y, $0.z)
            }
            let frame = ProjectArchitectureViewport.frame(points: points, size: viewport)
            let center = SCNVector3(frame.center.x, frame.center.y, frame.center.z)
            camera.position = SCNVector3(center.x, center.y, center.z + frame.distance)
            camera.look(at: center)
            view.defaultCameraController.target = center
            primeStaticFrame()
        }

        func focus(on id: String?) {
            guard focusedId != id else { return }
            focusedId = id
            guard let id else { fit(viewport: fittedSize, force: true); return }
            guard let view,
                  let target = view.scene?.rootNode.childNode(withName: "report:\(id)", recursively: false)?.position,
                  let camera = view.pointOfView else { return }
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.35
            let aspect = Float(max(parent.viewport.width, 1) / max(parent.viewport.height, 1))
            camera.position = SCNVector3(target.x, target.y, target.z + max(18, 12 / aspect))
            view.defaultCameraController.target = target
            camera.look(at: target)
            SCNTransaction.commit()
            primeStaticFrame()
        }
    }

    static func positions(for report: ProjectRepositoryGraph) -> [String: SCNVector3] {
        ProjectArchitectureLayout.positions(for: report)
    }

    private static func scene(for report: ProjectRepositoryGraph, viewport: CGSize) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor(Theme.bg)
        let positions = positions(for: report)
        let frame = ProjectArchitectureViewport.frame(points: positions.values.map {
            SIMD3<Float>($0.x, $0.y, $0.z)
        }, size: viewport)
        let center = SCNVector3(frame.center.x, frame.center.y, frame.center.z)
        let camera = SCNNode()
        camera.name = "report-camera"
        camera.camera = SCNCamera()
        camera.camera?.zFar = 2_000
        camera.camera?.fieldOfView = 57
        camera.position = SCNVector3(center.x, center.y, center.z + frame.distance)
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
            material.diffuse.contents = UIColor(ProjectArchitectureStyle.color(node.kind))
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
                let (minimum, maximum) = label.boundingBox
                // Place the top of the actual glyph bounds below the sphere.
                title.pivot = SCNMatrix4MakeTranslation((minimum.x + maximum.x) / 2, maximum.y, 0)
                title.name = visual.name
                title.position = SCNVector3(0, -Float(sphere.radius) - 0.6, 0)
                title.constraints = [SCNBillboardConstraint()]
                visual.addChildNode(title)
            }
        }
        return scene
    }

}
