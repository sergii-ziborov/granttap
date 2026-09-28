import SwiftUI
import SceneKit

/// RepoLens-style Cyberboard: module plates, segmented file towers, and evidenced roads.
struct ProjectTowerScene: UIViewRepresentable {
    let snapshot: ProjectTowerSnapshot
    @Binding var selectedPath: String?

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = Self.scene(for: snapshot)
        view.backgroundColor = ProjectTowerGeometry.void
        view.pointOfView = view.scene?.rootNode.childNode(withName: "tower-camera", recursively: false)
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = ProcessInfo.processInfo.isLowPowerModeEnabled ? 30 : 60
        view.isPlaying = true
        view.rendersContinuously = true
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        doubleTap.delegate = context.coordinator
        view.addGestureRecognizer(doubleTap)
        tap.require(toFail: doubleTap)
        context.coordinator.view = view
        context.coordinator.primeStaticFrame()
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.parent = self
        let neighbors = Set(snapshot.roads.filter {
            $0.source == selectedPath || $0.target == selectedPath
        }.flatMap { [$0.source, $0.target] })
        let modules = Dictionary(uniqueKeysWithValues: snapshot.towers.map { ($0.id, $0.module) })
        let module = selectedPath.flatMap { modules[$0] }
        for node in view.scene?.rootNode.childNodes ?? [] where node.name?.hasPrefix("tower:") == true {
            let path = String((node.name ?? "").dropFirst("tower:".count))
            let sameModule = module != nil && modules[path] == module
            node.opacity = selectedPath == nil || path == selectedPath || neighbors.contains(path)
                || sameModule ? 1 : 0.14
        }
        context.coordinator.focus(on: selectedPath)
        view.setNeedsDisplay()
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ProjectTowerScene
        weak var view: SCNView?
        private var frameTask: Task<Void, Never>?
        private var focusedPath: String?

        init(parent: ProjectTowerScene) { self.parent = parent }

        func primeStaticFrame() {
            frameTask?.cancel()
            frameTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard !Task.isCancelled, let view = self?.view else { return }
                view.rendersContinuously = false
                view.isPlaying = false
                view.setNeedsDisplay()
            }
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let path = hit(gesture) else { return }
            parent.selectedPath = path
        }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let path = hit(gesture) else { return }
            parent.selectedPath = path
            focus(on: path, force: true)
        }

        private func hit(_ gesture: UITapGestureRecognizer) -> String? {
            guard let view else { return nil }
            let hits = view.hitTest(gesture.location(in: view), options: [
                .searchMode: SCNHitTestSearchMode.closest.rawValue,
                .ignoreHiddenNodes: true,
            ])
            return hits.compactMap { $0.node.name }
                .first { $0.hasPrefix("tower:") }
                .map { String($0.dropFirst("tower:".count)) }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        func focus(on path: String?, force: Bool = false) {
            guard force || focusedPath != path else { return }
            focusedPath = path
            guard let path, let tower = parent.snapshot.towers.first(where: { $0.id == path }),
                  let camera = view?.pointOfView else { return }
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.35
            camera.position = SCNVector3(tower.x + 22, max(tower.height * 0.55, 10), tower.z + 28)
            camera.look(at: SCNVector3(tower.x, tower.height * 0.45, tower.z))
            SCNTransaction.commit()
        }
    }

    private static func scene(for snapshot: ProjectTowerSnapshot) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = ProjectTowerGeometry.void
        scene.fogColor = ProjectTowerGeometry.void
        addFloor(snapshot.plates, to: scene)
        addRoads(snapshot, to: scene)
        addTowers(snapshot.towers, to: scene)
        let camera = SCNNode()
        camera.name = "tower-camera"
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 56
        camera.camera?.projectionDirection = .horizontal
        let xs = snapshot.towers.map(\.x)
        let zs = snapshot.towers.map(\.z)
        let cx = ((xs.min() ?? 0) + (xs.max() ?? 0)) / 2
        let cz = ((zs.min() ?? 0) + (zs.max() ?? 0)) / 2
        let halfWidth = ((xs.max() ?? 20) - (xs.min() ?? -20)) / 2 + 16
        let halfDepth = ((zs.max() ?? 20) - (zs.min() ?? -20)) / 2 + 16
        let radius = sqrt(halfWidth * halfWidth + halfDepth * halfDepth)
        let distance = max(48, radius * 1.7)
        let height = snapshot.towers.map(\.height).max() ?? 10
        camera.camera?.zFar = Double(max(1_600, distance * 8))
        scene.fogStartDistance = CGFloat(max(220, distance * 2.6))
        scene.fogEndDistance = CGFloat(max(700, distance * 5.2))
        camera.position = SCNVector3(cx + distance * 0.3,
                                     max(42, height * 0.8, distance * 0.65), cz + distance)
        camera.look(at: SCNVector3(cx, min(height * 0.18, 18), cz))
        scene.rootNode.addChildNode(camera)
        return scene
    }

    private static func addFloor(_ plates: [ProjectTowerPlate], to scene: SCNScene) {
        guard !plates.isEmpty else { return }
        let minX = (plates.map { $0.cx - $0.half }.min() ?? -40) - 16
        let maxX = (plates.map { $0.cx + $0.half }.max() ?? 40) + 16
        let minZ = (plates.map { $0.cz - $0.half }.min() ?? -40) - 16
        let maxZ = (plates.map { $0.cz + $0.half }.max() ?? 40) + 16
        var grid: [SCNVector3] = []
        var x = floor(minX / ProjectTowerLayout.fileSpacing) * ProjectTowerLayout.fileSpacing
        while x <= maxX {
            grid += [SCNVector3(x, -0.04, minZ), SCNVector3(x, -0.04, maxZ)]
            x += ProjectTowerLayout.fileSpacing
        }
        var z = floor(minZ / ProjectTowerLayout.fileSpacing) * ProjectTowerLayout.fileSpacing
        while z <= maxZ {
            grid += [SCNVector3(minX, -0.04, z), SCNVector3(maxX, -0.04, z)]
            z += ProjectTowerLayout.fileSpacing
        }
        if let floor = ProjectTowerGeometry.lines(grid, color: ProjectTowerGeometry.cyan, opacity: 0.16) {
            scene.rootNode.addChildNode(floor)
        }
        for plate in plates {
            scene.rootNode.addChildNode(ProjectTowerGeometry.plate(plate))
            let x = plate.cx - plate.half
            let z = plate.cz - plate.half
            let right = plate.cx + plate.half
            let back = plate.cz + plate.half
            let border = [SCNVector3(x, 0.07, z), SCNVector3(right, 0.07, z),
                          SCNVector3(right, 0.07, z), SCNVector3(right, 0.07, back),
                          SCNVector3(right, 0.07, back), SCNVector3(x, 0.07, back),
                          SCNVector3(x, 0.07, back), SCNVector3(x, 0.07, z)]
            if let outline = ProjectTowerGeometry.lines(border, color: ProjectTowerGeometry.cyan,
                                                         opacity: 0.68) {
                scene.rootNode.addChildNode(outline)
            }
            scene.rootNode.addChildNode(ProjectTowerGeometry.label(
                plate.name.uppercased(), x: plate.cx - Float(plate.name.count) * 0.35,
                y: 0.32, z: plate.cz - plate.half - 3.2,
                color: ProjectTowerGeometry.cyan
            ))
        }
    }

    private static func addRoads(_ snapshot: ProjectTowerSnapshot, to scene: SCNScene) {
        let byPath = Dictionary(uniqueKeysWithValues: snapshot.towers.map { ($0.id, $0) })
        var grouped: [String: [SCNVector3]] = [:]
        for road in snapshot.roads {
            guard let from = byPath[road.source], let to = byPath[road.target] else { continue }
            let key = from.module == to.module ? "local" : road.relation
            let y: Float = 0.18
            let middle = SCNVector3((from.x + to.x) / 2, y, (from.z + to.z) / 2)
            grouped[key, default: []] += [SCNVector3(from.x, y, from.z),
                                           SCNVector3(middle.x, y, from.z),
                                           SCNVector3(middle.x, y, from.z), middle,
                                           middle, SCNVector3(to.x, y, to.z)]
        }
        for (kind, points) in grouped {
            let color: UIColor = switch kind {
            case "local": .gray
            case "imports", "re_exports": ProjectTowerGeometry.cyan
            case "calls": UIColor(red: 1, green: 77/255, blue: 166/255, alpha: 1)
            case "exposes", "consumes": UIColor(red: 1, green: 122/255, blue: 89/255, alpha: 1)
            default: UIColor(red: 1, green: 176/255, blue: 0, alpha: 1)
            }
            if let line = ProjectTowerGeometry.lines(points, color: color, opacity: 0.7) {
                scene.rootNode.addChildNode(line)
            }
        }
    }

    private static func addTowers(_ towers: [ProjectTower], to scene: SCNScene) {
        var standard: [SCNVector3] = []
        var entry: [SCNVector3] = []
        var dead: [SCNVector3] = []
        var documents: [SCNVector3] = []
        for tower in towers {
            scene.rootNode.addChildNode(ProjectTowerGeometry.tower(tower))
            if tower.isDead { appendRing(tower, to: &dead) }
            else if tower.isEntry { appendRing(tower, to: &entry) }
            else if tower.isDocument { appendRing(tower, to: &documents) }
            else { appendRing(tower, to: &standard) }
        }
        for tower in towers.filter({ ($0.isEntry || $0.isDead) && $0.id != "ext:rest-api" }).prefix(24) {
            scene.rootNode.addChildNode(ProjectTowerGeometry.label(
                tower.isDead ? "DEAD" : "ENTRY",
                x: tower.x - tower.width,
                y: tower.height + 0.8, z: tower.z,
                color: tower.isDead ? ProjectTowerGeometry.coral : ProjectTowerGeometry.mint
            ))
        }
        if let api = towers.first(where: { $0.id == "ext:rest-api" }) {
            scene.rootNode.addChildNode(ProjectTowerGeometry.label(
                "REST API", x: api.x - api.width, y: api.height + 0.8, z: api.z,
                color: ProjectTowerGeometry.coral
            ))
        }
        for tower in towers.filter({ $0.id.hasPrefix("ext:") && $0.id != "ext:rest-api" }) {
            scene.rootNode.addChildNode(ProjectTowerGeometry.label(
                String(tower.segments.first?.label.prefix(22) ?? "EXTERNAL"),
                x: tower.x - tower.width, y: tower.height + 0.8, z: tower.z,
                color: UIColor(red: 163/255, green: 113/255, blue: 247/255, alpha: 1)
            ))
        }
        for (points, color, opacity) in [
            (standard, ProjectTowerGeometry.cyan, CGFloat(0.58)),
            (entry, ProjectTowerGeometry.mint, CGFloat(0.96)),
            (dead, ProjectTowerGeometry.coral, CGFloat(0.92)),
            (documents, UIColor.gray, CGFloat(0.54)),
        ] {
            if let ring = ProjectTowerGeometry.lines(points, color: color, opacity: opacity) {
                scene.rootNode.addChildNode(ring)
            }
        }
    }

    private static func appendRing(_ tower: ProjectTower, to points: inout [SCNVector3]) {
        let radius = tower.width * 0.74
        for index in 0..<16 {
            let start = Float(index) / 16 * .pi * 2
            let end = Float(index + 1) / 16 * .pi * 2
            points += [SCNVector3(tower.x + cos(start) * radius, 0.12,
                                  tower.z + sin(start) * radius),
                       SCNVector3(tower.x + cos(end) * radius, 0.12,
                                  tower.z + sin(end) * radius)]
        }
    }
}
