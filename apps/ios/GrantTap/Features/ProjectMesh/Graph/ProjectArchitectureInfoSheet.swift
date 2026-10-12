import SwiftUI

enum ProjectArchitectureInfo: Identifiable {
    case report, components, component(String)
    var id: String {
        switch self {
        case .report: return "report"
        case .components: return "components"
        case .component(let id): return "component:\(id)"
        }
    }
}

/// Read the received report without implying that unknown repository facts were scanned.
struct ProjectArchitectureInfoSheet: View {
    let report: ProjectRepositoryGraph
    let repositoryName: String
    let destination: ProjectArchitectureInfo
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var detailId: String?

    private var componentId: String? {
        if let detailId { return detailId }
        if case .component(let id) = destination { return id }
        return nil
    }

    var body: some View {
        NavigationView {
            List {
                if let id = componentId, let node = report.nodes.first(where: { $0.id == id }) {
                    component(node)
                } else if case .report = destination {
                    reportDetails
                } else {
                    inventory
                }
            }
            .navigationTitle(componentId == nil ? L("Architecture report") : L("Component details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if detailId != nil {
                        Button(L("Back")) { detailId = nil }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var reportDetails: some View {
        Group {
            Section(L("How to read this graph")) {
                Text(L("Drag to rotate, pinch to zoom, and tap a component to inspect its connections. Reset fits the whole report to your screen."))
                Text(L("Arrows in component details follow the relation from source to target. Colours identify component types, not health or approval status."))
            }
            Section(L("Report scope")) {
                row(L("Repository"), repositoryName)
                row(L("Revision"), report.revision)
                row("Weavatrix", report.weavatrixVersion)
                row(L("Status"), report.analysisStatus ?? L("Legacy"))
                row(L("Components"), "\(report.nodes.count) / \(report.totalNodes)")
                row(L("Relations"), "\(report.relations.count) / \(report.totalRelations)")
                Text(L("Complete describes the reported analysis inputs. It does not prove that every dependency in the repository is known. Missing evidence stays unknown."))
                if report.truncated {
                    Label(L("Partial evidence: some components, relations, or inputs are missing."),
                          systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                if let error = report.analysisErrorCode { Text(error).textSelection(.enabled) }
            }
            Section(L("Component types")) {
                ForEach(Array(Set(report.nodes.map(\.kind))).sorted(), id: \.self) { kind in
                    HStack {
                        Circle().fill(ProjectArchitectureStyle.color(kind)).frame(width: 12, height: 12)
                        Text(kind.capitalized)
                        Spacer()
                        Text("\(report.nodes.filter { $0.kind == kind }.count)").foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }

    private var inventory: some View {
        Group {
            Section {
                TextField(L("Find a component"), text: $query).autocorrectionDisabled()
                    .accessibilityIdentifier("architecture.inventory.search")
            }
            Section(L("Components")) {
                let nodes = report.nodes.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
                    .filter { query.isEmpty || $0.label.localizedStandardContains(query)
                        || $0.kind.localizedStandardContains(query) || $0.id.localizedStandardContains(query) }
                if nodes.isEmpty { Text(L("No matching components")).foregroundStyle(Theme.muted) }
                ForEach(nodes) { node in
                    Button { detailId = node.id } label: {
                        HStack {
                            Circle().fill(ProjectArchitectureStyle.color(node.kind)).frame(width: 10, height: 10)
                            VStack(alignment: .leading) {
                                Text(node.label)
                                Text(node.kind.capitalized).font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                        }
                    }
                    .accessibilityIdentifier("architecture.component.\(node.id)")
                }
            }
        }
    }

    private func component(_ node: ProjectRepositoryGraph.Node) -> some View {
        Group {
            Section {
                row(L("Component"), node.label)
                row(L("Type"), node.kind.capitalized)
                row(L("Identifier"), node.id)
                Button(L("Show on graph")) { onSelect(node.id); dismiss() }
                    .accessibilityIdentifier("architecture.show-on-graph")
            }
            Section(L("Component relations")) {
                let edges = report.relations.filter { $0.source == node.id || $0.target == node.id }
                if edges.isEmpty { Text(L("No relations in this report")).foregroundStyle(Theme.muted) }
                ForEach(edges) { edge in
                    let other = edge.source == node.id ? edge.target : edge.source
                    Button { detailId = other } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(label(edge.source)) → \(label(edge.target))")
                            Text(edge.evidenceCount.map { "\(edge.relation) · \(L("Evidence")): \($0)" }
                                 ?? "\(edge.relation) · \(L("Evidence count unknown"))")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            Section(L("Report scope")) {
                row(L("Revision"), report.revision)
                Text(L("Only connections contained in this received report are shown. A component with no reported relations is not necessarily independent."))
            }
        }
    }

    private func label(_ id: String) -> String { report.nodes.first { $0.id == id }?.label ?? id }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Theme.muted)
            Text(value).textSelection(.enabled)
        }
    }
}

enum ProjectArchitectureStyle {
    static func color(_ kind: String) -> Color {
        switch kind {
        case "workspace": return Theme.ok
        case "package": return Theme.riskMed
        default: return Theme.codex
        }
    }
}
