import Foundation
import simd

enum ProjectTowerCameraAction: Equatable {
    case zoomIn, zoomOut, fit, top, isometric, focus, orbitLeft, orbitRight
}

struct ProjectTowerCameraRequest: Equatable {
    let id = UUID()
    let action: ProjectTowerCameraAction
}

enum ProjectTowerNavigationMode: String, CaseIterable {
    case orbit = "Orbit", pan = "Pan"
}

struct ProjectTowerViewSettings: Equatable {
    enum Highlight: String, CaseIterable {
        case links = "Connected towers", module = "Same module", all = "All towers"
    }
    var highlight: Highlight = .links
    var dimOpacity = 0.18
    var labels = true
    var roads = true
    var autoFocus = true
    var navigation: ProjectTowerNavigationMode = .orbit
}

/// Camera positions are computed from measured scene bounds and the selected source section.
struct ProjectTowerCameraPose: Equatable {
    let position: SIMD3<Float>
    let target: SIMD3<Float>

    static func overview(_ snapshot: ProjectTowerSnapshot, aspect: Float = 1, top: Bool = false) -> Self {
        let minX = snapshot.towers.map(\.x).min() ?? -20
        let maxX = snapshot.towers.map(\.x).max() ?? 20
        let minZ = snapshot.towers.map(\.z).min() ?? -20
        let maxZ = snapshot.towers.map(\.z).max() ?? 20
        let height = snapshot.towers.map(\.height).max() ?? 10
        let center = SIMD3<Float>((minX + maxX) / 2, min(height * 0.18, 18), (minZ + maxZ) / 2)
        let radius = hypot((maxX - minX) / 2 + 16, (maxZ - minZ) / 2 + 16)
        let distance = max(48, radius * 2.1 * max(1, aspect))
        let offset = top ? SIMD3<Float>(0, distance, 0.01)
            : SIMD3<Float>(distance * 0.3, max(42, distance * 0.65), distance)
        return Self(position: center + offset, target: center)
    }

    func zoomed(_ factor: Float) -> Self {
        let offset = position - target
        let distance = simd_length(offset)
        guard distance > 0, factor.isFinite, factor > 0 else { return self }
        return Self(position: target + offset / distance * min(12_000, max(8, distance * factor)), target: target)
    }

    func orbited(_ radians: Float) -> Self {
        let d = position - target
        let rotated = SIMD3<Float>(d.x * cos(radians) + d.z * sin(radians), d.y,
                                  d.z * cos(radians) - d.x * sin(radians))
        return Self(position: target + rotated, target: target)
    }

    static func focus(_ tower: ProjectTower, symbolId: String?) -> Self {
        let section = ProjectTowerSectionGeometry.section(tower, id: symbolId)
        let height = section?.center ?? tower.height * 0.45
        let distance = max(18, min(90, (section?.height ?? tower.height) * 1.8 + 18))
        let target = SIMD3<Float>(tower.x, height, tower.z)
        return Self(position: target + SIMD3<Float>(distance * 0.55, distance * 0.4, distance), target: target)
    }
}

enum ProjectTowerSectionGeometry {
    struct Section: Equatable { let id: String; let center: Float; let height: Float }

    static func section(_ tower: ProjectTower, id: String?) -> Section? {
        var bottom: Float = 0
        for segment in tower.segments {
            defer { bottom += segment.height + ProjectTowerLayout.segmentGap }
            if segment.id == id { return Section(id: segment.id, center: bottom + segment.height / 2, height: segment.height) }
        }
        return nil
    }

    static func hit(_ tower: ProjectTower, height: Float) -> String? {
        var bottom: Float = 0
        for segment in tower.segments {
            if height >= bottom && height <= bottom + segment.height { return segment.id }
            bottom += segment.height + ProjectTowerLayout.segmentGap
        }
        return nil
    }
}
