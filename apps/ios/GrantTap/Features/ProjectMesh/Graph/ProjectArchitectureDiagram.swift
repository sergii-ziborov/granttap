import SwiftUI

struct ProjectArchitectureDiagram: View {
    let report: ProjectRepositoryGraph
    let repositoryName: String
    @State private var showRelations = false
    @State private var showHypotheses = false
    @State private var showFullGraph = false
    @State private var showTowers = false
    @State private var showReportDetails = false

    private var nodes: [String: ProjectRepositoryGraph.Node] {
        report.nodes.reduce(into: [:]) { result, node in result[node.id] = node }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if report.analysisStatus == "UNAVAILABLE" {
                EmptyView()
            } else if report.analysisStatus == nil {
                Text(L("This computer sent a legacy graph without an architecture analysis. Update GrantTap Engine to inspect verified component relations."))
                    .foregroundStyle(.orange)
            } else {
                if let map = report.codeMap, !map.files.isEmpty {
                    Button { showTowers = true } label: {
                        mapAction("Code map", detail: "Files, functions and source checks", icon: "building.2.crop.circle")
                    }
                    .accessibilityIdentifier("architecture.towers.\(report.repositoryId)")
                }
                Button { showFullGraph = true } label: {
                    mapAction("Architecture", detail: "Components and dependencies", icon: "point.3.connected.trianglepath.dotted")
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
                if let hypotheses = report.architectureHypotheses, !hypotheses.isEmpty {
                    DisclosureGroup(L("Architecture hypotheses"), isExpanded: $showHypotheses) {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(hypotheses) { hypothesis in hypothesisRow(hypothesis) }
                        }
                    }
                }
            }
            reportDetails
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
                Text(statusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(report.analysisStatus == "COMPLETE" && !report.truncated ? .green : .orange)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Theme.bg, in: Capsule())
            }
            if report.analysisStatus == "UNAVAILABLE" {
                Text(unavailableReason)
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Text(String(format: L("%d components · %d relations"),
                            report.totalNodes, report.totalRelations))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }

    private var unavailableReason: String {
        ProjectRepositoryGraph.unavailableReason(report.analysisErrorCode)
    }

    private var statusTitle: String {
        if report.analysisStatus == "UNAVAILABLE" { return L("Analysis unavailable") }
        if report.truncated || report.analysisStatus == "INCOMPLETE" { return L("Partial report") }
        return report.analysisStatus == "COMPLETE" ? L("Ready") : L("Legacy")
    }

    private func mapAction(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(L(title)).font(.subheadline.weight(.semibold))
                Text(L(detail)).font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }

    private var reportDetails: some View {
        DisclosureGroup(L("Report details"), isExpanded: $showReportDetails) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Weavatrix \(report.weavatrixVersion)")
                Text("\(L("Analysis fingerprint")): \(report.revision)").textSelection(.enabled)
                if let revision = report.sourceRevision {
                    Text("\(L("Source revision")): \(revision)").textSelection(.enabled)
                }
                if report.truncated || report.analysisStatus == "INCOMPLETE" {
                    Text(L("Partial evidence: some components, relations, or inputs are missing."))
                }
            }
            .font(.caption).foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
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
