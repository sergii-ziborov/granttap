import SceneKit
import UIKit

enum ProjectTowerHighlighting {
    static func apply(_ snapshot: ProjectTowerSnapshot, to scene: SCNScene?, path: String?,
                      symbol: String?, settings: ProjectTowerViewSettings) {
        guard let scene else { return }
        let neighbors = Set(snapshot.roads.filter { $0.source == path || $0.target == path }
            .flatMap { [$0.source, $0.target] })
        let selected = snapshot.towers.first { $0.id == path }
        for node in scene.rootNode.childNodes {
            let name = node.name ?? ""
            if name.hasPrefix("label:") { node.isHidden = !settings.labels }
            if name.hasPrefix("roads:") { node.isHidden = !settings.roads }
            guard name.hasPrefix("tower:") else { continue }
            let id = String(name.dropFirst("tower:".count))
            guard let tower = snapshot.towers.first(where: { $0.id == id }) else { continue }
            let relevant = settings.highlight == .all || id == path
                || (settings.highlight == .links && neighbors.contains(id))
                || (settings.highlight == .module && selected?.module == tower.module)
            node.opacity = path == nil || relevant ? 1 : min(1, max(0.04, settings.dimOpacity))
            node.childNode(withName: "selected-section", recursively: false)?.removeFromParentNode()
            guard id == path, let section = ProjectTowerSectionGeometry.section(tower, id: symbol) else { continue }
            let box = SCNBox(width: CGFloat(tower.width + 0.25), height: CGFloat(section.height + 0.12),
                             length: CGFloat(tower.width + 0.25), chamferRadius: 0)
            let material = ProjectTowerGeometry.material(ProjectTowerGeometry.mint)
            material.fillMode = .lines
            box.materials = [material]
            let outline = SCNNode(geometry: box)
            outline.name = "selected-section"
            outline.categoryBitMask = 2
            outline.position.y = section.center
            node.addChildNode(outline)
        }
    }
}
