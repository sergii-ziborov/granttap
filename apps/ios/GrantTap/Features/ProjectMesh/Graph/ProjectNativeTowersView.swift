import SwiftUI

/// Full-screen measured code city with persistent controls and source inspection.
struct ProjectNativeTowersView: View {
    let report: ProjectRepositoryGraph
    let repositoryName: String
    let map: ProjectCodeMap
    @State private var snapshot: ProjectTowerSnapshot
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedPath: String?
    @State private var selectedSymbol: String?
    @State private var command: ProjectTowerCameraRequest?
    @State private var settings = ProjectTowerViewSettings()
    @State private var colorMode: ProjectTowerColorMode = .language
    @State private var showBrowser = false
    @State private var showSettings = false
    @State private var showHelp = false
    @State private var immersive = false
    @State private var queuedSelection: (String, String?)?
    @FocusState private var searchFocused: Bool

    init(report: ProjectRepositoryGraph, repositoryName: String, map: ProjectCodeMap) {
        self.report = report
        self.repositoryName = repositoryName
        self.map = map
        _snapshot = State(initialValue: ProjectTowerLayout.build(map))
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > 850
            VStack(spacing: 8) {
                if !immersive { toolbar.layoutPriority(1) }
                HStack(alignment: .top, spacing: 10) {
                    ProjectTowerScene(snapshot: snapshot, selectedPath: $selectedPath,
                        selectedSymbol: $selectedSymbol, command: command, settings: settings)
                        .accessibilityIdentifier("code-towers.scene")
                    if wide && !immersive && selectedPath != nil { inspector.frame(width: 340) }
                }
                if !wide && !immersive && selectedPath != nil {
                    inspector.frame(maxHeight: min(280, geometry.size.height * 0.36))
                }
                ProjectTowerCameraDock(settings: $settings, selected: selectedPath != nil) { act($0) }
                if !immersive { summary }
            }
            .padding(immersive ? 0 : 12)
            .overlay(alignment: .topTrailing) {
                if immersive {
                    Button { immersive = false } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .frame(width: 44, height: 44).background(.regularMaterial, in: Circle())
                    }
                    .accessibilityLabel(L("Show graph panels")).padding(12)
                }
            }
        }
        .background(Color(red: 5/255, green: 6/255, blue: 10/255).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $showBrowser, onDismiss: applyQueuedSelection) {
            ProjectTowerBrowser(map: map) { path, symbol in queuedSelection = (path, symbol) }
        }
        .sheet(isPresented: $showSettings) {
            ProjectTowerSettingsSheet(settings: $settings, colorMode: $colorMode)
        }
        .sheet(isPresented: $showHelp) { ProjectTowerControlsHelp() }
        .onChange(of: colorMode) { mode in snapshot = ProjectTowerLayout.build(map, colorMode: mode) }
        .onChange(of: map) { value in
            snapshot = ProjectTowerLayout.build(value, colorMode: colorMode)
            if let selectedPath, !snapshot.towers.contains(where: { $0.id == selectedPath }) {
                self.selectedPath = nil
                selectedSymbol = nil
            } else if let selectedPath, let selectedSymbol,
                      let tower = snapshot.towers.first(where: { $0.id == selectedPath }),
                      !tower.segments.contains(where: { $0.id == selectedSymbol }) {
                self.selectedSymbol = nil
            }
        }
    }

    private var inspector: some View {
        ProjectTowerInspector(report: report, map: map, snapshot: snapshot,
            selectedPath: $selectedPath, selectedSymbol: $selectedSymbol) { act(.focus) }
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel(L("Close code towers"))
                VStack(alignment: .leading, spacing: 2) {
                    Text(repositoryName).font(.headline).lineLimit(1)
                    Text("Weavatrix \(report.weavatrixVersion) · \(report.analysisStatus ?? L("Unknown"))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { showBrowser = true } label: {
                    Image(systemName: "list.bullet").frame(width: 44, height: 44)
                }
                .accessibilityLabel(L("Browse graph files")).accessibilityIdentifier("code-towers.files")
                Menu {
                    Button(L("Top view")) { act(.top) }
                    Button(L("Isometric view")) { act(.isometric) }
                    Button(L("Rotate left")) { act(.orbitLeft) }
                    Button(L("Rotate right")) { act(.orbitRight) }
                    Divider()
                    Button(L("View settings")) { showSettings = true }
                    Button(L("Graph controls")) { showHelp = true }
                    Button(L("Hide graph panels")) { immersive = true }
                } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }
                .accessibilityLabel(L("Graph view options"))
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Find a file or symbol"), text: $query)
                    .autocorrectionDisabled().focused($searchFocused)
                    .accessibilityIdentifier("code-towers.search")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel(L("Clear search"))
                }
            }
            .padding(10).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            if !query.isEmpty { searchResults }
        }
        .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .pointerButtonStyle()
    }

    private var searchResults: some View {
        ProjectTowerSearchResults(map: map, query: query) { path, symbol in
            select(path, symbol: symbol)
        }
    }

    private var summary: some View {
        HStack {
            Text("\(snapshot.towers.count)/\(map.totalFiles + (map.totalExternals ?? 0)) \(L("code towers"))")
            Spacer()
            Text(ProjectCodeMapScope(map).partialTitle ?? report.analysisStatus ?? L("Unknown"))
        }
        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
    }

    private func act(_ action: ProjectTowerCameraAction) { command = ProjectTowerCameraRequest(action: action) }

    private func select(_ path: String, symbol: String?) {
        selectedPath = path
        selectedSymbol = symbol
        query = ""
        searchFocused = false
    }

    private func applyQueuedSelection() {
        guard let value = queuedSelection else { return }
        queuedSelection = nil
        select(value.0, symbol: value.1)
    }
}
