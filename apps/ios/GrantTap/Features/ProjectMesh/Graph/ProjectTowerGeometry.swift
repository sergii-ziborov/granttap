import SceneKit
import UIKit
import simd

enum ProjectTowerGeometry {
    static let void = UIColor(red: 5/255, green: 6/255, blue: 10/255, alpha: 1)
    static let cyan = UIColor(red: 77/255, green: 232/255, blue: 1, alpha: 1)
    static let mint = UIColor(red: 39/255, green: 232/255, blue: 154/255, alpha: 1)
    static let coral = UIColor(red: 1, green: 122/255, blue: 89/255, alpha: 1)

    static func material(_ color: UIColor, opacity: CGFloat = 1) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color
        material.lightingModel = .constant
        material.transparency = opacity
        material.isDoubleSided = true
        return material
    }

    static func tower(_ tower: ProjectTower) -> SCNNode {
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var grouped: [UInt32: [UInt32]] = [:]
        var y: Float = 0
        for segment in tower.segments {
            let color = packed(segment.color)
            appendBox(width: tower.width, bottom: y, top: y + segment.height,
                      vertices: &vertices, normals: &normals,
                      indices: &grouped[color, default: []])
            y += segment.height + ProjectTowerLayout.segmentGap
        }
        let colors = grouped.keys.sorted()
        let elements = colors.map { SCNGeometryElement(indices: grouped[$0] ?? [], primitiveType: .triangles) }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices),
                                              SCNGeometrySource(normals: normals)], elements: elements)
        geometry.materials = colors.map { material(uiColor($0)) }
        let node = SCNNode(geometry: geometry)
        node.name = "tower:\(tower.id)"
        node.position = SCNVector3(tower.x, 0, tower.z)
        return node
    }

    static func lines(_ points: [SCNVector3], color: UIColor, opacity: CGFloat) -> SCNNode? {
        guard !points.isEmpty else { return nil }
        let source = SCNGeometrySource(vertices: points)
        let element = SCNGeometryElement(indices: points.indices.map(Int32.init), primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.materials = [material(color, opacity: opacity)]
        return SCNNode(geometry: geometry)
    }

    static func plate(_ plate: ProjectTowerPlate) -> SCNNode {
        let geometry = SCNPlane(width: CGFloat(plate.half * 2), height: CGFloat(plate.half * 2))
        geometry.materials = [material(UIColor(red: 22/255, green: 27/255, blue: 38/255, alpha: 1),
                                       opacity: 0.92)]
        let node = SCNNode(geometry: geometry)
        node.eulerAngles.x = -.pi / 2
        node.position = SCNVector3(plate.cx, 0.02, plate.cz)
        return node
    }

    static func label(_ value: String, x: Float, y: Float, z: Float, color: UIColor) -> SCNNode {
        let text = SCNText(string: value, extrusionDepth: 0.08)
        text.font = UIFont.monospacedSystemFont(ofSize: 2, weight: .semibold)
        text.flatness = 0.3
        text.materials = [material(color)]
        let node = SCNNode(geometry: text)
        node.scale = SCNVector3(0.34, 0.34, 0.34)
        node.position = SCNVector3(x, y, z)
        node.constraints = [SCNBillboardConstraint()]
        return node
    }

    private static func packed(_ color: SIMD3<Float>) -> UInt32 {
        let r = UInt32((min(1, max(0, color.x)) * 255).rounded())
        let g = UInt32((min(1, max(0, color.y)) * 255).rounded())
        let b = UInt32((min(1, max(0, color.z)) * 255).rounded())
        return (r << 16) | (g << 8) | b
    }

    private static func uiColor(_ value: UInt32) -> UIColor {
        UIColor(red: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
    }

    private static func appendBox(width: Float, bottom: Float, top: Float,
                                  vertices: inout [SCNVector3], normals: inout [SCNVector3],
                                  indices: inout [UInt32]) {
        let half = width / 2
        let faces: [(SCNVector3, [SCNVector3])] = [
            (SCNVector3(0, 0, 1), [SCNVector3(-half, bottom, half), SCNVector3(half, bottom, half),
                                    SCNVector3(half, top, half), SCNVector3(-half, top, half)]),
            (SCNVector3(0, 0, -1), [SCNVector3(half, bottom, -half), SCNVector3(-half, bottom, -half),
                                     SCNVector3(-half, top, -half), SCNVector3(half, top, -half)]),
            (SCNVector3(1, 0, 0), [SCNVector3(half, bottom, half), SCNVector3(half, bottom, -half),
                                    SCNVector3(half, top, -half), SCNVector3(half, top, half)]),
            (SCNVector3(-1, 0, 0), [SCNVector3(-half, bottom, -half), SCNVector3(-half, bottom, half),
                                     SCNVector3(-half, top, half), SCNVector3(-half, top, -half)]),
            (SCNVector3(0, 1, 0), [SCNVector3(-half, top, half), SCNVector3(half, top, half),
                                    SCNVector3(half, top, -half), SCNVector3(-half, top, -half)]),
            (SCNVector3(0, -1, 0), [SCNVector3(-half, bottom, -half), SCNVector3(half, bottom, -half),
                                     SCNVector3(half, bottom, half), SCNVector3(-half, bottom, half)])
        ]
        for (normal, face) in faces {
            let base = UInt32(vertices.count)
            vertices.append(contentsOf: face)
            normals.append(contentsOf: Array(repeating: normal, count: 4))
            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }
    }
}
