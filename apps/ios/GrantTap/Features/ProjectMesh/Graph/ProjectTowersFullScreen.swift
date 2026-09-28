import SwiftUI

/// Full-screen code city backed by measured files and Weavatrix symbol/edge evidence.
struct ProjectTowersFullScreen: View {
    let report: ProjectRepositoryGraph
    let repositoryName: String
    let map: ProjectCodeMap
    @State private var snapshot: ProjectTowerSnapshot
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedPath: String?
    @State private var reset = 0
    @State private var colorMode: ProjectTowerColorMode = .language
    @FocusState private var searchFocused: Bool

    init(report: ProjectRepositoryGraph, repositoryName: String, map: ProjectCodeMap) {
        self.report = report
        self.repositoryName = repositoryName
        self.map = map
        _snapshot = State(initialValue: ProjectTowerLayout.build(map))
    }

    private var selectedFile: ProjectCodeMap.File? {
        map.files.first { $0.path == selectedPath }
    }

    private var selectedExternal: ProjectCodeMap.External? {
        map.externals?.first { $0.id == selectedPath }
    }

    private var matches: [ProjectCodeMap.File] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return Array(map.files.filter { file in
            file.path.localizedStandardContains(needle)
                || file.symbols.contains { $0.label.localizedStandardContains(needle) }
        }.prefix(20))
    }

    private var externalMatches: [ProjectCodeMap.External] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return Array((map.externals ?? []).filter {
            $0.label.localizedStandardContains(needle) || $0.kind.localizedStandardContains(needle)
        }.prefix(20))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 5/255, green: 6/255, blue: 10/255).ignoresSafeArea()
            ProjectTowerScene(snapshot: snapshot, selectedPath: $selectedPath)
                .id(reset)
                .ignoresSafeArea()
                .accessibilityIdentifier("code-towers.scene")
                .allowsHitTesting(query.isEmpty)
            VStack(spacing: 8) {
                toolbar
                if !matches.isEmpty || !externalMatches.isEmpty { results }
                Spacer()
                if let selectedFile { inspector(selectedFile) }
                else if let selectedExternal { externalInspector(selectedExternal) }
                else if selectedPath == "ext:rest-api",
                        let tower = snapshot.towers.first(where: { $0.id == "ext:rest-api" }) {
                    apiInspector(tower)
                }
                summary
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
        .environment(\.colorScheme, .dark)
        .onChange(of: colorMode) { mode in
            snapshot = ProjectTowerLayout.build(map, colorMode: mode)
            reset += 1
        }
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline).frame(width: 40, height: 40)
                }
                .accessibilityLabel(L("Close code towers"))
                VStack(alignment: .leading, spacing: 2) {
                    Text(repositoryName).font(.headline).lineLimit(1)
                    Text("Weavatrix \(report.weavatrixVersion) · \(report.revision.prefix(12))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Picker(L("Color"), selection: $colorMode) {
                        ForEach(ProjectTowerColorMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                } label: {
                    Image(systemName: "paintpalette").frame(width: 40, height: 40)
                }
                .accessibilityLabel(L("Tower colors"))
                Button { reset += 1; selectedPath = nil } label: {
                    Image(systemName: "arrow.counterclockwise").frame(width: 40, height: 40)
                }
                .accessibilityLabel(L("Reset tower view"))
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Find a file or symbol"), text: $query)
                    .autocorrectionDisabled()
                    .focused($searchFocused)
                    .accessibilityIdentifier("code-towers.search")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel(L("Clear search"))
                }
            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var results: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(matches) { file in
                    Button {
                        selectedPath = file.path
                        query = ""
                        searchFocused = false
                    } label: {
                        HStack {
                            Text(file.path).lineLimit(1)
                            Spacer()
                            Text(file.language ?? "—").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                ForEach(externalMatches) { external in
                    Button {
                        selectedPath = external.id
                        query = ""
                        searchFocused = false
                    } label: {
                        HStack {
                            Text(external.label).lineLimit(1)
                            Spacer()
                            Text(external.kind).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: 240)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func inspector(_ file: ProjectCodeMap.File) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(file.path).font(.headline).lineLimit(2).textSelection(.enabled)
                    .accessibilityIdentifier("code-towers.inspector.path")
                Spacer()
                Button { selectedPath = nil } label: { Image(systemName: "xmark.circle") }
                    .accessibilityLabel(L("Close file details"))
            }
            Text(file.lineCount.map { "\($0) LOC" } ?? L("Line count unavailable"))
                .font(.caption).foregroundStyle(file.lineCount == nil ? .orange : .secondary)
            if !file.symbols.isEmpty {
                Text(file.symbols.prefix(5).map { "\($0.kind) \($0.label) · \($0.startLine)" }
                    .joined(separator: "\n"))
                    .font(.caption.monospaced())
                    .lineLimit(5)
            }
            let related = snapshot.roads.filter { $0.source == file.path || $0.target == file.path }
            if !related.isEmpty {
                Text(String(format: L("%d evidenced links"), related.count))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func apiInspector(_ tower: ProjectTower) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("REST API").font(.headline)
                Spacer()
                Button { selectedPath = nil } label: { Image(systemName: "xmark.circle") }
                    .accessibilityLabel(L("Close API details"))
            }
            Text("\(tower.lineCount ?? tower.segments.count) \(L("observed endpoints"))")
                .font(.caption).foregroundStyle(.secondary)
            Text(tower.segments.prefix(12).map(\.label).joined(separator: "\n"))
                .font(.caption.monospaced()).lineLimit(12)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func externalInspector(_ external: ProjectCodeMap.External) -> some View {
        let related = snapshot.roads.filter { $0.source == external.id || $0.target == external.id }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(external.label).font(.headline).lineLimit(2).textSelection(.enabled)
                    .accessibilityIdentifier("code-towers.inspector.external")
                Spacer()
                Button { selectedPath = nil } label: { Image(systemName: "xmark.circle") }
                    .accessibilityLabel(L("Close external details"))
            }
            Text(external.kind).font(.caption).foregroundStyle(.secondary)
            Text(String(format: L("%d evidenced links"), related.count))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var summary: some View {
        HStack(spacing: 8) {
            Text("\(map.files.count)/\(map.totalFiles) \(L("files")) · \((map.externals ?? []).count) \(L("external resources")) · \(snapshot.roads.count) \(L("relations"))")
            Spacer()
            if map.truncated { Text(L("Partial map")).foregroundStyle(.orange) }
            else if map.files.contains(where: { $0.lineCount == nil }) {
                Text(L("Some LOC unknown")).foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
