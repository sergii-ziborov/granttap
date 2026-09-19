import SwiftUI

struct ProjectMeshStatusView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @State private var toast: String?

    var bindings: [ProjectBindingSummary] {
        ProjectMeshLogic.visibleBindings(snapshot.bindings ?? []).sorted {
            $0.displayName == $1.displayName
                ? $0.bindingId < $1.bindingId : $0.displayName < $1.displayName
        }
    }

    var peers: [ProjectIntegrationPeer] {
        (snapshot.peers ?? []).sorted { $0.id < $1.id }
    }

    var repoLens: ProjectRepoLensPresentation.Graph {
        ProjectRepoLensPresentation.graph(snapshot)
    }

    var body: some View {
        List {
            Section {
                ProjectRepoLensGraphView(graph: repoLens)
                if repoLens.edges.isEmpty && repoLens.nodes.count <= 1 {
                    Text(L("Commit a WEAVATRIX.md in a bound repository to draw the other side of this repo."))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            } header: {
                Text(L("Repo lens"))
            } footer: {
                Text(repoLens.rowDetail)
            }
            Section(L("Mesh")) {
                CompatLabeledContent(
                    L("Mode"), value: ProjectManagePresentation.meshSummary(snapshot)
                )
                CompatLabeledContent(L("Tasks"), value: "\(snapshot.tasks.count)")
                CompatLabeledContent(L("Executions"), value: "\(snapshot.executions.count)")
                if snapshot.incomplete == true {
                    Text(L("Bounded snapshot. Not the whole Project."))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            }
            projectUsageSection
            Section(L("Repository bindings")) {
                if bindings.isEmpty {
                    Text(L("No repository bindings reported."))
                        .foregroundColor(Theme.muted)
                } else {
                    ForEach(bindings) { binding in ProjectBindingRow(binding: binding, model: model) }
                }
            }
            Section {
                if peers.isEmpty {
                    Text(L("No integration edges reported yet."))
                        .font(.caption).foregroundStyle(Theme.muted)
                } else {
                    ForEach(peers) { peer in ProjectIntegrationPeerRow(peer: peer, snapshot: snapshot) }
                }
            } header: {
                Text(L("Integration map"))
            } footer: {
                Text(L("From WEAVATRIX.md in each bound repository. Only stated edges are shown."))
            }
        }
        .navigationTitle(L("Health / Graph"))
        .transientToast($toast)
    }

    /// A Project is the only scope that spans machines, so it is the only one
    /// that can answer which machine is carrying it — and every number here
    /// opens: a computer to what it did, a tool to its calls, a call to the
    /// chat at the moment it happened.
    @ViewBuilder private var projectUsageSection: some View {
        let sessionIds = ProjectUsageStats.sessionIds(snapshot)
        let events = ProjectUsageStats.events(
            CapabilityUsageStore.shared.events, snapshot: snapshot
        )
        inventorySection(events: events)
        if !events.isEmpty {
            if let totals = TaskUsageHistory.totals(events, sessionIds: sessionIds) {
                Section(L("This Project")) {
                    CompatLabeledContent(L("Calls"), value: "\(totals.calls)")
                    if totals.failures > 0 {
                        CompatLabeledContent(L("Failed"), value: "\(totals.failures)")
                    }
                    if let cpu = totals.cpuTimeMs {
                        CompatLabeledContent(L("CPU time"), value: CapabilityResourceFormat.duration(cpu))
                    }
                    if let peak = totals.peakMemoryBytes {
                        CompatLabeledContent(L("Peak memory"), value: CapabilityResourceFormat.bytes(peak))
                    }
                    CompatLabeledContent(
                        L("Tokens"), value: Format.tokens(ProjectUsageStats.tokens(
                            model.sessions + model.allSessionHistory, sessionIds: sessionIds
                        ))
                    )
                }
            }
            let now = Date().timeIntervalSince1970 * 1_000
            let buckets = UsageTimeline.buckets(
                events, since: now - 24 * 3_600_000, until: now
            )
            if !buckets.isEmpty {
                Section {
                    UsageTimelineChart(buckets: buckets, accent: Theme.accent(for: "claude"))
                } header: {
                    Text(L("Last 24 hours"))
                } footer: {
                    Text(L("Calls over time across every computer in this Project."))
                }
            }
            let summaries = TaskUsageHistory.summaries(events, sessionIds: sessionIds)
            let shares = UsageBreakdown.shares(summaries)
            if !shares.isEmpty {
                Section {
                    UsageBreakdownChart(shares: shares)
                } header: {
                    Text(L("Where the time went"))
                }
            }
        }
    }

    @ViewBuilder
    private func inventorySection(
        events: [CapabilityUsageEvent]
    ) -> some View {
        let computers = ProjectUsageStats.inventory(events, snapshot: snapshot)
        Section(L("Load by computer")) {
            if computers.isEmpty {
                Text(L("No computers reported yet."))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            ForEach(computers) { row in
                NavigationLink {
                    ProjectComputerUsageView(
                        endpointId: row.endpointId, snapshot: snapshot, model: model
                    )
                } label: {
                    ProjectComputerUsageRow(
                        usage: row, model: model,
                        work: ProjectComputerWork.current(
                            snapshot: snapshot, endpointId: row.endpointId, sessions: model.sessions
                        )
                    )
                }
                .accessibilityIdentifier("mesh.computer.\(row.endpointId)")
            }
        }
        let catalog = ProjectToolsSkillsPresentation.catalog(
            snapshot: snapshot,
            sessions: model.sessions + model.allSessionHistory,
            usage: events,
            added: model.addedToolItems(for: snapshot.projectId)
        )
        Section {
            if catalog.skills.isEmpty && catalog.servers.isEmpty {
                Text(L("Usage not yet observed"))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            ForEach(catalog.servers + catalog.skills) { item in
                Text([
                    item.name,
                    ProjectToolsSkillsPresentation.stateLabel(item.state),
                    item.version.map { "\(L("Desired")) \($0)" },
                    ProjectToolsSkillsPresentation.usageLabel(name: item.name, usedNames: catalog.usedNames),
                ].compactMap { $0 }.joined(separator: " · "))
                    .accessibilityIdentifier("mesh.inventory.\(item.name)")
            }
        } header: {
            Text(L("Tools"))
        } footer: {
            Text(events.isEmpty
                 ? L("Usage not yet observed")
                 : L("Touch and hold a tool to allow, ask, or deny it for this Project."))
        }
    }
}

struct ProjectComputerUsageRow: View {
    let usage: ProjectComputerUsage
    @ObservedObject var model: AppModel
    var work: [ProjectComputerWork.Item] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(displayName).lineLimit(1)
                Spacer(minLength: 8)
                Text(String(format: L("%d×"), usage.calls))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            if let line = ProjectComputerWork.line(work) {
                Text(line).font(.caption)
                    .foregroundStyle(work.first?.working == true ? Theme.ok : Theme.muted)
                    .lineLimit(2)
            }
            if let detail {
                Text(detail).font(.caption).foregroundStyle(Theme.muted)
            }
            if usage.failures > 0 {
                Text(String(format: L("%d failed"), usage.failures))
                    .font(.caption).foregroundStyle(Theme.riskHigh)
            }
        }
        .padding(.vertical, 2)
    }

    private var displayName: String {
        model.connectionRegistry.connections
            .first { $0.id == usage.endpointId }?.displayName ?? usage.endpointId
    }

    private var detail: String? {
        let parts = [
            usage.cpuTimeMs.map { CapabilityResourceFormat.duration($0) },
            usage.peakMemoryBytes.map { CapabilityResourceFormat.bytes($0) },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct ProjectBindingRow: View {
    let binding: ProjectBindingSummary
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: binding.available ? "externaldrive.fill.badge.checkmark" : "externaldrive")
                .frame(width: 24).foregroundColor(binding.available ? Theme.ok : Theme.muted)
            VStack(alignment: .leading, spacing: 3) {
                Text(binding.displayName.isEmpty ? binding.repositoryId : binding.displayName)
                Text(detail).font(.caption).foregroundColor(Theme.muted).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    var detail: String {
        let computer = model.connectionRegistry.connections
            .first(where: { $0.id == binding.endpointId })?.displayName
            ?? shortEndpoint(binding.endpointId)
        let revision = binding.revision.map { String($0.prefix(12)) }
        return [computer, revision].compactMap { $0 }.joined(separator: " · ")
    }

    func shortEndpoint(_ endpoint: String) -> String {
        endpoint.count <= 24 ? endpoint : "\(L("Computer")) \(endpoint.prefix(8))"
    }
}

struct ProjectIntegrationPeerRow: View {
    let peer: ProjectIntegrationPeer
    let snapshot: ProjectMeshSnapshot

    /// The far side is bound in this Project, so the Mesh can watch it.
    var bound: Bool {
        !ProjectOtherSide.otherSides(of: peer.repositoryId, in: snapshot)
            .filter { $0.peer == peer }.isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: bound ? "point.3.connected.trianglepath.dotted" : "point.3.filled.connected.trianglepath.dotted")
                .frame(width: 24).foregroundColor(bound ? Theme.ok : Theme.muted)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(ProjectOtherSide.displayName(of: peer.repositoryId, in: snapshot)) → \(peer.peer)")
                Text([peer.via, ProjectOtherSide.phrase(relation: peer.relation, through: peer.through),
                      bound ? L("bound in this Project") : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundColor(Theme.muted).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Repositories as nodes, WEAVATRIX edges as lines. One repo still draws.
struct ProjectRepoLensGraphView: View {
    let graph: ProjectRepoLensPresentation.Graph

    var body: some View {
        GeometryReader { geometry in
            let positions = layout(in: geometry.size)
            ZStack {
                ForEach(graph.edges) { edge in
                    if let from = positions[edge.from], let to = positions[edge.to] {
                        Path { path in
                            path.move(to: from)
                            path.addLine(to: to)
                        }
                        .stroke(Theme.line, lineWidth: 1.5)
                    }
                }
                ForEach(graph.nodes) { node in
                    if let point = positions[node.id] {
                        Text(node.title)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(node.working ? Theme.ok.opacity(0.18) : Theme.raised)
                            )
                            .overlay(
                                Capsule().stroke(node.working ? Theme.ok : Theme.line, lineWidth: 1)
                            )
                            .position(point)
                    }
                }
            }
        }
        .frame(minHeight: graph.nodes.count <= 1 ? 88 : 200)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.repo-lens")
        .accessibilityLabel(graph.rowDetail)
    }

    private func layout(in size: CGSize) -> [String: CGPoint] {
        let ids = graph.nodes.map(\.id)
        guard !ids.isEmpty else { return [:] }
        let center = CGPoint(x: max(size.width, 1) / 2, y: max(size.height, 1) / 2)
        if ids.count == 1 { return [ids[0]: center] }
        let radius = min(size.width, size.height) * 0.34
        var points: [String: CGPoint] = [:]
        for (index, id) in ids.enumerated() {
            let angle = (Double(index) / Double(ids.count)) * Double.pi * 2 - Double.pi / 2
            points[id] = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
        }
        return points
    }
}
