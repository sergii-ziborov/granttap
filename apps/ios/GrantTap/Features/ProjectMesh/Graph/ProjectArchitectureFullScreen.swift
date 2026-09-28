import SwiftUI

/// The whole bounded Weavatrix report, with selection and search over every reported node.
struct ProjectArchitectureFullScreen: View {
    let report: ProjectRepositoryGraph
    let repositoryName: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedId: String?
    @State private var reset = 0
    @State private var showAllRelations = false
    @FocusState private var searchFocused: Bool

    private var selected: ProjectRepositoryGraph.Node? {
        report.nodes.first { $0.id == selectedId }
    }

    private var matches: [ProjectRepositoryGraph.Node] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return Array(report.nodes.filter {
            $0.label.localizedStandardContains(needle) || $0.kind.localizedStandardContains(needle)
        }.prefix(20))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()
            ProjectArchitectureScene(report: report, selectedId: $selectedId)
                .id(reset)
                .ignoresSafeArea()
                .accessibilityIdentifier("architecture.scene")
                .allowsHitTesting(query.isEmpty)
            VStack(spacing: 8) {
                toolbar
                if !matches.isEmpty { results }
                Spacer()
                if let selected { inspector(selected) }
                summary
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 18)
            .zIndex(1)
        }
        .sheet(isPresented: $showAllRelations) {
            NavigationView {
                List {
                    ForEach(selectedRelations) { edge in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(label(edge.source)) → \(label(edge.target))")
                            Text(edge.evidenceCount.map {
                                "\(edge.relation) · \($0) \(L("observed links"))"
                            } ?? "\(edge.relation) · \(L("Evidence count unknown"))")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
                .navigationTitle(L("Component relations"))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Done")) { showAllRelations = false }
                    }
                }
            }
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
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel(L("Close graph"))
                VStack(alignment: .leading) {
                    Text(repositoryName).font(.headline).lineLimit(1)
                    Text("Weavatrix \(report.weavatrixVersion) · \(report.revision.prefix(12))")
                        .font(.caption2).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button { reset += 1; selectedId = nil } label: {
                    Image(systemName: "arrow.counterclockwise").frame(width: 40, height: 40)
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
                    .buttonStyle(.plain)
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
            Text(node.kind.capitalized).font(.caption).foregroundStyle(Theme.muted)
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
                .buttonStyle(.plain)
                .font(.caption)
            }
            if selectedRelations.count > 4 {
                Button(String(format: L("Show all %d relations"), selectedRelations.count)) {
                    showAllRelations = true
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var summary: some View {
        HStack {
            Text(String(format: L("%d of %d components · %d of %d relations"),
                        report.nodes.count, report.totalNodes,
                        report.relations.count, report.totalRelations))
            Spacer()
            Text(report.truncated ? L("Partial report") : (report.analysisStatus ?? L("Legacy")))
                .foregroundStyle(report.truncated ? .orange : Theme.muted)
        }
        .font(.caption)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
