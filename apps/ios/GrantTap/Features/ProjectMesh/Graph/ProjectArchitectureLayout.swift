import SceneKit
import simd

/// A bounded, deterministic three-dimensional force layout for Engine evidence.
/// Repository input order cannot change where a component appears.
enum ProjectArchitectureLayout {
    static func positions(for report: ProjectRepositoryGraph) -> [String: SCNVector3] {
        let nodes = report.nodes.sorted { $0.id < $1.id }
        guard !nodes.isEmpty else { return [:] }
        let indices = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($0.element.id, $0.offset) })
        let links = report.relations.compactMap { relation -> (Int, Int, String)? in
            guard let source = indices[relation.source], let target = indices[relation.target],
                  source != target else { return nil }
            return (source, target, relation.id)
        }.sorted { $0.2 < $1.2 }
        var points = nodes.enumerated().map { index, node -> SIMD3<Float> in
            let angle = unit(node.id, 1) * 2 * .pi
            let radius = 3 + sqrt(Float(index)) * 2.2
            return SIMD3(cos(angle) * radius, sin(angle) * radius,
                         (unit(node.id, 2) - 0.5) * radius * 1.3)
        }
        var velocity = Array(repeating: SIMD3<Float>.zero, count: nodes.count)
        let iterations = nodes.count > 160 ? 24 : 40
        for _ in 0..<iterations {
            var force = Array(repeating: SIMD3<Float>.zero, count: nodes.count)
            repel(points, into: &force)
            for (source, target, _) in links {
                let delta = points[target] - points[source]
                let distance = max(simd_length(delta), 0.001)
                let spring = delta / distance * (distance - 7) * 0.055
                force[source] += spring
                force[target] -= spring
            }
            for index in points.indices {
                force[index] -= points[index] * 0.008
                velocity[index] = (velocity[index] + force[index]) * 0.82
                let speed = simd_length(velocity[index])
                if speed > 2.1 { velocity[index] *= 2.1 / speed }
                points[index] += velocity[index]
            }
        }
        return Dictionary(uniqueKeysWithValues: nodes.enumerated().map { index, node in
            let point = points[index]
            return (node.id, SCNVector3(point.x, point.y, point.z))
        })
    }

    private static func repel(_ points: [SIMD3<Float>], into force: inout [SIMD3<Float>]) {
        guard points.count > 1 else { return }
        for left in 0..<(points.count - 1) {
            for right in (left + 1)..<points.count {
                let delta = points[left] - points[right]
                let distanceSquared = max(simd_length_squared(delta), 0.01)
                let push = delta / sqrt(distanceSquared) * (19 / (distanceSquared + 4))
                force[left] += push
                force[right] -= push
            }
        }
    }

    private static func unit(_ id: String, _ salt: UInt64) -> Float {
        var hash: UInt64 = 14_695_981_039_346_656_037 ^ salt
        for byte in id.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return Float(hash % 1_000_003) / 1_000_003
    }
}
