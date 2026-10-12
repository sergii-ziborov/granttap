import SwiftUI

/// The whole bounded Weavatrix report, with selection and search over every reported node.
struct ProjectArchitectureFullScreen: View {
    let report: ProjectRepositoryGraph
    let repositoryName: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedId: String?
    @State private var reset = 0
    @State private var info: ProjectArchitectureInfo?
    @FocusState private var searchFocused: Bool

    private var selected: ProjectRepositoryGraph.Node? {
        report.nodes.first { $0.id == selectedId }
    }

    private var matches: [ProjectRepositoryGraph.Node] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return report.nodes.filter {
            $0.label.localizedStandardContains(needle) || $0.kind.localizedStandardContains(needle)
                || $0.id.localizedStandardContains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            toolbar
            if !query.isEmpty { results }
            GeometryReader { geometry in
                ProjectArchitectureScene(report: report, selectedId: $selectedId, viewport: geometry.size)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .id(reset)
                    .accessibilityIdentifier("architecture.scene")
            }
            .overlay(alignment: .bottomLeading) {
                if selected == nil {
                    Label(L("Tap a component to inspect"), systemImage: "hand.tap")
                        .font(.caption).foregroundStyle(Theme.muted)
                        .padding(10).allowsHitTesting(false)
                }
            }
            if let selected { inspector(selected) }
            summary
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Theme.bg.ignoresSafeArea())
        .sheet(item: $info) { destination in
            ProjectArchitectureInfoSheet(report: report, repositoryName: repositoryName,
                                         destination: destination) { selectedId = $0 }
        }
    }

    private var selectedRelations: [ProjectRepositoryGraph.Relation] {
        guard let selectedId else { return [] }
        return report.relations.filter { $0.source == selectedId || $0.target == selectedId }
    }

    private func label(_ id: String) -> String {
        report.nodes.first { $0.id == id }?.label ?? id
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(L("Close graph"))
                VStack(alignment: .leading) {
                    Text(repositoryName).font(.headline).lineLimit(1)
                    Text("Weavatrix \(report.weavatrixVersion) · \(report.revision.prefix(12))")
                        .font(.caption2).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button { info = .report } label: {
                    Image(systemName: "info.circle").frame(width: 44, height: 44)
                }
                .accessibilityLabel(L("About this graph"))
                .accessibilityIdentifier("architecture.info")
                Button { reset += 1; selectedId = nil; query = ""; searchFocused = false } label: {
                    Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44)
                }
                .accessibilityLabel(L("Reset graph view"))
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField(L("Find a component"), text: $query)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("architecture.search")
                    .focused($searchFocused)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel(L("Clear search"))
                }
            }
            .padding(10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var results: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if matches.isEmpty {
                    Text(L("No matching components")).foregroundStyle(Theme.muted).padding(12)
                }
                ForEach(matches) { node in
                    Button {
                        selectedId = node.id
                        query = ""
                        searchFocused = false
                    } label: {
                        HStack {
                            Text(node.label).lineLimit(1)
                            Spacer()
                            Text(node.kind).font(.caption).foregroundStyle(Theme.muted)
                        }
                        .padding(10)
                        .contentShape(Rectangle())
                    }
                    .pointerButtonStyle()
                    .accessibilityIdentifier("architecture.result.\(node.id)")
                }
            }
        }
        .frame(maxHeight: 240)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func inspector(_ node: ProjectRepositoryGraph.Node) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(node.label).font(.headline).textSelection(.enabled)
                    .accessibilityIdentifier("architecture.inspector.title")
                Spacer()
                Button { selectedId = nil } label: { Image(systemName: "xmark.circle") }
                    .accessibilityLabel(L("Close component details"))
            }
            HStack {
                Circle().fill(ProjectArchitectureStyle.color(node.kind)).frame(width: 10, height: 10)
                Text(node.kind.capitalized).font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                Button(L("Component details")) { info = .component(node.id) }
                    .font(.caption)
                    .accessibilityIdentifier("architecture.component-info")
            }
            ForEach(selectedRelations.prefix(4)) { edge in
                let otherId = edge.source == node.id ? edge.target : edge.source
                let other = report.nodes.first { $0.id == otherId }
                Button {
                    selectedId = otherId
                } label: {
                    HStack {
                        Text(edge.source == node.id ? "→" : "←")
                        Text(other?.label ?? otherId).lineLimit(1)
                        Spacer()
                        Text(edge.relation).foregroundStyle(Theme.muted)
                    }
                    .contentShape(Rectangle())
                }
                .pointerButtonStyle()
                .font(.caption)
            }
            if selectedRelations.count > 4 {
                Button(String(format: L("Show all %d relations"), selectedRelations.count)) {
                    info = .component(node.id)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var summary: some View {
        HStack(spacing: 12) {
            Button { info = .components } label: {
                Label(String(format: L("%d components · %d relations"),
                             report.nodes.count, report.relations.count), systemImage: "list.bullet")
                    .multilineTextAlignment(.leading)
            }
            .accessibilityIdentifier("architecture.components")
            Spacer()
            Button { info = .report } label: {
                Label(report.truncated ? L("Partial report") : (report.analysisStatus ?? L("Legacy")),
                      systemImage: report.truncated ? "exclamationmark.circle" : "info.circle")
                    .foregroundStyle(report.truncated ? .orange : Theme.muted)
            }
        }
        .font(.caption)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
