import Foundation
import simd

struct ProjectTowerSegment: Hashable {
    let id: String
    let label: String
    let height: Float
    let color: SIMD3<Float>
}

struct ProjectTower: Hashable, Identifiable {
    let id: String
    let x: Float
    let z: Float
    let module: String
    let language: String?
    let lineCount: Int?
    let segments: [ProjectTowerSegment]
    let isEntry: Bool
    let isDocument: Bool
    let hasRoad: Bool
    var width: Float { id == "ext:rest-api" ? 6 : id.hasPrefix("ext:") ? 5.2 : 2.6 }
    var isDead: Bool { !id.hasPrefix("ext:") && !isEntry && !isDocument && !hasRoad }
    var height: Float { segments.reduce(0) { $0 + $1.height + ProjectTowerLayout.segmentGap } }
}

struct ProjectTowerPlate: Hashable, Identifiable {
    var id: String { name }
    let name: String
    let cx: Float
    let cz: Float
    let half: Float
}

struct ProjectTowerSnapshot: Hashable {
    let towers: [ProjectTower]
    let plates: [ProjectTowerPlate]
    let roads: [ProjectCodeMap.Road]
    let totalFiles: Int
    let truncated: Bool
}

enum ProjectTowerColorMode: String, CaseIterable, Identifiable {
    case language, kind, connections
    var id: String { rawValue }
    var title: String {
        switch self {
        case .language: return L("Language")
        case .kind: return L("Kind")
        case .connections: return L("Connections")
        }
    }
}

enum ProjectTowerLayout {
    // Match RepoLens Cyberboard geometry so height, spacing, and grouping carry the same meaning.
    static let heightPerLoc: Float = 0.085
    static let segmentGap: Float = 0.45
    static let fileSpacing: Float = 16
    static let moduleGap: Float = 26

    static func build(_ map: ProjectCodeMap,
                      colorMode: ProjectTowerColorMode = .language) -> ProjectTowerSnapshot {
        let groups = Dictionary(grouping: map.files) { file in
            let parts = file.path.split(separator: "/")
            return parts.count > 1 ? String(parts[0]) : "(root)"
        }
        let names = groups.keys.sorted()
        let columns = max(1, Int(ceil(sqrt(Double(names.count)))))
        let rows = max(1, Int(ceil(Double(names.count) / Double(columns))))
        let largestHalf = names.map { name -> Float in
            let grid = max(1, Int(ceil(sqrt(Double(groups[name]?.count ?? 0)))))
            return Float(grid) * fileSpacing / 2 + 4
        }.max() ?? 30
        let cell = largestHalf * 2 + moduleGap
        let connected = Set(map.roads.flatMap { [$0.source, $0.target] })
        let degree = map.roads.reduce(into: [String: Int]()) { result, road in
            result[road.source, default: 0] += 1
            result[road.target, default: 0] += 1
        }
        var plates: [ProjectTowerPlate] = []
        var towers: [ProjectTower] = []

        for (index, name) in names.enumerated() {
            let files = (groups[name] ?? []).sorted { $0.path < $1.path }
            let grid = max(1, Int(ceil(sqrt(Double(files.count)))))
            let half = Float(grid) * fileSpacing / 2 + 4
            let cx = (Float(index % columns) - Float(columns - 1) / 2) * cell
            let cz = (Float(index / columns) - Float(rows - 1) / 2) * cell
            plates.append(ProjectTowerPlate(name: name, cx: cx, cz: cz, half: half))
            for (fileIndex, file) in files.enumerated() {
                let x = cx + (Float(fileIndex % grid) - Float(grid - 1) / 2) * fileSpacing
                let z = cz + (Float(fileIndex / grid) - Float(grid - 1) / 2) * fileSpacing
                towers.append(ProjectTower(
                    id: file.path, x: x, z: z, module: name, language: file.language,
                    lineCount: file.lineCount,
                    segments: segments(file, mode: colorMode, degree: degree[file.path] ?? 0),
                    isEntry: isEntry(file.path) || file.symbols.contains {
                        $0.kind.lowercased() == "endpoint"
                    }, isDocument: isDocument(file.path),
                    hasRoad: connected.contains(file.path)
                ))
            }
        }
        if !(map.externals ?? []).isEmpty {
            let minX = plates.map { $0.cx - $0.half }.min() ?? -40
            let externalNodes = (map.externals ?? []).sorted { $0.id < $1.id }
            for (index, node) in externalNodes.enumerated() {
                let connections = degree[node.id] ?? 0
                towers.append(ProjectTower(
                    id: node.id, x: minX - 28,
                    z: (Float(index) - Float(externalNodes.count - 1) / 2) * 10,
                    module: "external", language: nil, lineCount: nil,
                    segments: [ProjectTowerSegment(id: node.id, label: node.label,
                        height: max(4, Float(connections) * 0.45 + 3), color: rgb(0xA371F7))],
                    isEntry: false, isDocument: false, hasRoad: connections > 0
                ))
            }
        }
        let endpoints = map.files.flatMap { file in
            file.symbols.filter { $0.kind.lowercased() == "endpoint" }
                .map { (path: file.path, symbol: $0) }
        }
        var roads = map.roads
        if !endpoints.isEmpty {
            let maxX = plates.map { $0.cx + $0.half }.max() ?? 40
            let visible = Array(endpoints.prefix(80))
            towers.append(ProjectTower(
                id: "ext:rest-api", x: maxX + 28, z: 0, module: "api", language: nil,
                lineCount: endpoints.count,
                segments: visible.map { item in
                    ProjectTowerSegment(id: item.symbol.id, label: item.symbol.label,
                                        height: 1.8, color: rgb(0xFF7A59))
                },
                isEntry: true, isDocument: false, hasRoad: true
            ))
            for path in Set(visible.map(\.path)).sorted() {
                roads.append(ProjectCodeMap.Road(source: path, target: "ext:rest-api",
                                                relation: "exposes"))
            }
        }
        return ProjectTowerSnapshot(towers: towers, plates: plates, roads: roads,
                                    totalFiles: map.totalFiles, truncated: map.truncated)
    }

    static func compressedHeight(_ loc: Int) -> Float {
        let lines = Float(max(0, loc))
        let soft: Float = 100
        let k: Float = 600
        let effective = lines <= soft ? lines : soft + (lines - soft) / (1 + (lines - soft) / k)
        return max(0.6, effective * heightPerLoc)
    }

    private static func segments(_ file: ProjectCodeMap.File, mode: ProjectTowerColorMode,
                                 degree: Int) -> [ProjectTowerSegment] {
        let document = isDocument(file.path)
        let symbols = file.symbols.filter { $0.kind.lowercased() != "endpoint" }
        let baseColor = file.lineCount == nil ? rgb(0x6E7681) : color(for: file.language,
                                                                  kind: "file", degree: degree,
                                                                  mode: mode)
        if document || symbols.isEmpty {
            let lines = document ? compressedDocumentLines(file.lineCount ?? 1) : file.lineCount ?? 1
            return [ProjectTowerSegment(id: file.path, label: file.path,
                                        height: compressedHeight(lines), color: baseColor)]
        }
        return symbols.map { symbol in
            ProjectTowerSegment(id: symbol.id, label: symbol.label,
                                height: compressedHeight(symbol.lineCount),
                                color: color(for: file.language, kind: symbol.kind,
                                             degree: degree, mode: mode))
        }
    }

    private static func compressedDocumentLines(_ lines: Int) -> Int {
        min(44, max(6, Int((6 + log2(Double(max(1, lines)) + 1) * 4.5).rounded())))
    }

    private static func color(for language: String?, kind: String, degree: Int,
                              mode: ProjectTowerColorMode) -> SIMD3<Float> {
        switch mode {
        case .language: return languageColor(language)
        case .kind: return kindColor(kind)
        case .connections:
            let value = min(1, Float(degree) / 20)
            return SIMD3(0.3 + value * 0.7, 0.85 - value * 0.6, 1 - value * 0.7)
        }
    }

    private static func isDocument(_ path: String) -> Bool {
        let path = path.lowercased()
        return [".md", ".mdx", ".markdown", ".rst", ".adoc"].contains { path.hasSuffix($0) }
    }

    private static func isEntry(_ path: String) -> Bool {
        let value = path.lowercased()
        let stem = URL(fileURLWithPath: value).deletingPathExtension().lastPathComponent
        return ["index", "main", "server", "app", "cli", "bootstrap", "entry", "run",
                "manage", "wsgi", "asgi"].contains(stem)
            || value.hasPrefix("cmd/") || value.contains("/cmd/")
            || value.hasPrefix("bin/") || value.contains("/bin/")
    }

    private static func languageColor(_ language: String?) -> SIMD3<Float> {
        switch language?.lowercased() {
        case "swift", "cpp", "c++": rgb(0x58A6FF)
        case "typescript", "tsx", "sql": rgb(0x4DE8FF)
        case "javascript", "jsx", "json": rgb(0xFFB000)
        case "python": rgb(0x3572A5)
        case "go": rgb(0x00ADD8)
        case "rust", "html": rgb(0xFF7A59)
        case "kotlin", "css", "scss", "terraform": rgb(0xA371F7)
        case "yaml", "yml", "protobuf": rgb(0x27E89A)
        case "markdown", "md": rgb(0x83A598)
        default: rgb(0x8B949E)
        }
    }

    private static func kindColor(_ kind: String) -> SIMD3<Float> {
        switch kind {
        case "function", "method": rgb(0x4DE8FF)
        case "struct", "enum", "class": rgb(0xFF4DA6)
        case "trait", "protocol": rgb(0x27E89A)
        case "endpoint": rgb(0xFF7A59)
        case "constant", "static": rgb(0xFFB000)
        default: rgb(0x58A6FF)
        }
    }

    private static func rgb(_ value: UInt32) -> SIMD3<Float> {
        SIMD3(Float((value >> 16) & 255) / 255,
              Float((value >> 8) & 255) / 255,
              Float(value & 255) / 255)
    }
}
