import SwiftUI

struct ProjectArchitectureDiagram: View {
    let report: ProjectRepositoryGraph
    let repositoryName: String
    @State private var showRelations = false
    @State private var showHypotheses = false
    @State private var showFullGraph = false
    @State private var showTowers = false

    private var nodes: [String: ProjectRepositoryGraph.Node] {
        report.nodes.reduce(into: [:]) { result, node in result[node.id] = node }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let hypotheses = report.architectureHypotheses, !hypotheses.isEmpty {
                DisclosureGroup(L("Architecture hypotheses"), isExpanded: $showHypotheses) {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(hypotheses) { hypothesis in
                            hypothesisRow(hypothesis)
                        }
                    }
                }
            }
            if report.analysisStatus == "UNAVAILABLE" {
                Text(unavailableReason)
                    .foregroundStyle(.orange)
            } else if report.analysisStatus == nil {
                Text(L("This computer sent a legacy graph without an architecture analysis. Update GrantTap Engine to inspect verified component relations."))
                    .foregroundStyle(.orange)
            } else {
                if let map = report.codeMap, !map.files.isEmpty {
                    Button { showTowers = true } label: {
                        Label(L("Open code towers full screen"), systemImage: "building.2.crop.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityIdentifier("architecture.towers.\(report.repositoryId)")
                }
                Button { showFullGraph = true } label: {
                    Label(L("Open full graph"), systemImage: "arrow.up.left.and.arrow.down.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("architecture.fullscreen.\(report.repositoryId)")
                if report.relations.isEmpty {
                    Text(L("No cross-component relations were observed in this bounded analysis."))
                        .foregroundStyle(Theme.muted)
                    componentInventory
                }
                if !report.relations.isEmpty {
                    DisclosureGroup(L("Relations in this report"), isExpanded: $showRelations) {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(report.relations) { edge in
                                relationRow(edge)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .fullScreenCover(isPresented: $showFullGraph) {
            ProjectArchitectureFullScreen(report: report, repositoryName: repositoryName)
        }
        .fullScreenCover(isPresented: $showTowers) {
            if let map = report.codeMap {
                ProjectTowersFullScreen(report: report, repositoryName: repositoryName, map: map)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(repositoryName).font(.headline)
                Spacer()
                Text(report.analysisStatus ?? L("Legacy"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(report.analysisStatus == "COMPLETE" ? .green : .orange)
            }
            if report.analysisStatus == "UNAVAILABLE" {
                Text(report.analysisErrorCode ?? "ENGINE_UNAVAILABLE")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Text("Weavatrix \(report.weavatrixVersion) · \(report.revision.prefix(12))")
                    .font(.caption).foregroundStyle(Theme.muted)
                Text(String(format: L("%d components · %d relations"),
                            report.totalNodes, report.totalRelations))
                    .font(.caption).foregroundStyle(Theme.muted)
                if report.truncated || report.analysisStatus == "INCOMPLETE" {
                    Text(L("Partial evidence: some components, relations, or inputs are missing."))
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    private var unavailableReason: String {
        switch report.analysisErrorCode {
        case "REPOSITORY_IDENTITY_MISMATCH":
            return L("This Mesh's saved checkout now belongs to another repository. Review its computer binding.")
        case "REPOSITORY_IDENTITY_UNVERIFIED":
            return L("The bound checkout's repository identity could not be verified.")
        case "REPOSITORY_NOT_BOUND":
            return L("This computer did not verify a Mesh binding for this repository. Build architecture now to refresh its bindings and retry.")
        case "REPOSITORY_NOT_LOCAL", "WEAVATRIX_REPOSITORY_REQUIRED":
            return L("No local Git checkout is available for architecture analysis on this computer.")
        default:
            return L("Architecture analysis is unavailable on this computer.")
        }
    }

    private var componentInventory: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(report.nodes) { node in
                HStack(spacing: 7) {
                    Image(systemName: node.kind == "package" ? "shippingbox" : "square.stack.3d.up")
                    Text(node.label).lineLimit(2)
                    Spacer()
                    Text(node.kind).foregroundStyle(Theme.muted)
                }
                .font(.caption)
            }
        }
    }

    private func hypothesisRow(_ item: ProjectRepositoryGraph.ArchitectureHypothesis) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(item.name.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(item.status.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.status == "SUPPORTED" ? .green : Theme.muted)
            }
            Text(item.dimension.replacingOccurrences(of: "_", with: " "))
                .font(.caption).foregroundStyle(Theme.muted)
            ForEach(item.evidence.prefix(8), id: \.self) { line in
                Text(line).font(.caption).textSelection(.enabled)
            }
            ForEach(item.contradictions.prefix(4), id: \.self) { line in
                Label(line, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if item.evidence.isEmpty {
                Text(L("No confirming code relations observed."))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            if !item.unknowns.isEmpty {
                Text(item.unknowns.prefix(2).joined(separator: " · "))
                    .font(.caption2).foregroundStyle(Theme.muted)
            }
        }
        .padding(10)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 12))
    }

    private func relationRow(_ edge: ProjectRepositoryGraph.Relation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 7) {
                nodeCard(edge.source)
                Image(systemName: "arrow.right")
                    .foregroundStyle(Theme.codex)
                nodeCard(edge.target)
            }
            HStack {
                Text(edge.relation)
                Spacer()
                if let count = edge.evidenceCount {
                    Text(String(format: L("%d observed links"), count))
                } else {
                    Text(L("Evidence count unknown"))
                }
            }
            .font(.caption2).foregroundStyle(Theme.muted)
        }
        .padding(10)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 12))
    }

    private func nodeCard(_ id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(nodes[id]?.label ?? id).font(.caption.weight(.semibold)).lineLimit(3)
            Text(nodes[id]?.kind ?? L("Unknown component"))
                .font(.caption2).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.codex.opacity(0.25)))
    }
}
