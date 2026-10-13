import Foundation

/// Received source facts for the tower inspector and its file browser.
enum ProjectTowerInspection {
    struct SourceSection: Identifiable, Equatable {
        let path: String
        let symbol: ProjectCodeMap.Symbol
        var id: String { "\(path)\u{0}\(symbol.id)" }
    }

    struct BrowserFile: Identifiable, Equatable {
        let file: ProjectCodeMap.File
        let symbols: [ProjectCodeMap.Symbol]
        var id: String { file.path }
    }

    struct BrowserGroup: Identifiable, Equatable {
        let name: String
        let files: [BrowserFile]
        var id: String { name }
    }

    static func sections(path: String, map: ProjectCodeMap) -> [SourceSection] {
        if let file = map.files.first(where: { $0.path == path }) {
            return file.symbols.map { SourceSection(path: path, symbol: $0) }
        }
        guard path == "ext:rest-api" else { return [] }
        return map.files.flatMap { file in
            file.symbols.filter { $0.kind.lowercased() == "endpoint" }
                .map { SourceSection(path: file.path, symbol: $0) }
        }
    }

    static func browserGroups(map: ProjectCodeMap, query: String) -> [BrowserGroup] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = map.files.compactMap { file -> BrowserFile? in
            let symbols = needle.isEmpty ? [] : file.symbols.filter {
                $0.label.localizedStandardContains(needle)
            }
            guard needle.isEmpty || file.path.localizedStandardContains(needle) || !symbols.isEmpty else {
                return nil
            }
            return BrowserFile(file: file, symbols: symbols)
        }
        let grouped = Dictionary(grouping: matches) { value in
            let components = value.file.path.split(separator: "/")
            return components.count > 1 ? String(components[0]) : "(root)"
        }
        return grouped.keys.sorted().map { name in
            BrowserGroup(name: name, files: (grouped[name] ?? []).sorted { $0.id < $1.id })
        }
    }

    static func links(path: String, roads: [ProjectCodeMap.Road]) -> [ProjectCodeMap.Road] {
        Array(Set(roads.filter { $0.source == path || $0.target == path })).sorted { $0.id < $1.id }
    }

    static func displayName(path: String, map: ProjectCodeMap) -> String {
        if path == "ext:rest-api" { return "REST API" }
        return map.externals?.first(where: { $0.id == path })?.label ?? path
    }
}
