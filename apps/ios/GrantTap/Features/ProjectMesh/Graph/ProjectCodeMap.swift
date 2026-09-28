import Foundation

/// Bounded source evidence from the same Weavatrix repository revision as the architecture report.
struct ProjectCodeMap: Codable, Equatable {
    struct File: Codable, Equatable, Identifiable {
        let path: String
        let language: String?
        let lineCount: Int?
        let symbols: [Symbol]
        var id: String { path }
    }

    struct Symbol: Codable, Equatable, Identifiable {
        let id: String
        let label: String
        let kind: String
        let startLine: Int
        let lineCount: Int
    }

    struct Road: Codable, Hashable, Identifiable {
        let source: String
        let target: String
        let relation: String
        var id: String { "\(source)\u{0}\(relation)\u{0}\(target)" }
    }

    struct External: Codable, Equatable, Identifiable {
        let id: String
        let label: String
        let kind: String
    }

    let files: [File]
    var externals: [External]? = nil
    let roads: [Road]
    let totalFiles: Int
    var totalExternals: Int? = nil
    let truncated: Bool

    func valid() -> Bool {
        let externalNodes = externals ?? []
        guard files.count <= 650, externalNodes.count <= 24, roads.count <= 1_200,
              totalFiles >= files.count, (totalExternals ?? 0) >= externalNodes.count else { return false }
        let paths = Set(files.map(\.path))
        let externalIds = Set(externalNodes.map(\.id))
        guard paths.count == files.count && externalIds.count == externalNodes.count,
              paths.isDisjoint(with: externalIds),
              externalNodes.allSatisfy({ $0.id.hasPrefix("ext:") && $0.id.count <= 512
                  && $0.id.count > 4 && $0.label.count <= 160 && !$0.kind.isEmpty
                  && $0.kind.count <= 64 }) else { return false }
        return files.allSatisfy { file in
            Self.validPath(file.path) && (file.language?.count ?? 0) <= 64
                && (file.lineCount.map { $0 > 0 } ?? true)
                && file.symbols.count <= 72
                && Set(file.symbols.map(\.id)).count == file.symbols.count
                && file.symbols.allSatisfy { symbol in
                    !symbol.id.isEmpty && symbol.id.count <= 512
                        && symbol.label.count <= 160 && !symbol.kind.isEmpty
                        && symbol.kind.count <= 64 && symbol.startLine > 0
                        && symbol.lineCount > 0
                }
        } && roads.allSatisfy { road in
            (paths.contains(road.source) || externalIds.contains(road.source))
                && (paths.contains(road.target) || externalIds.contains(road.target))
                && !road.relation.isEmpty && road.relation.count <= 64
        }
    }

    private static func validPath(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 512 && !value.hasPrefix("/")
            && !value.split(separator: "/").contains("..")
    }
}
