import SwiftUI

struct ProjectKnowledgeView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @State private var showingDecisionEditor = false
    @StateObject private var sync = ProjectKnowledgeRefresh()

    private var currentSnapshot: ProjectMeshSnapshot {
        model.meshSnapshots[snapshot.projectId] ?? snapshot
    }

    private var invocations: [ProjectInvocationRecord] {
        ProjectKnowledgePresentation.invocations(model.invocationHistoryByTask, snapshot: currentSnapshot)
    }

    private var summary: ProjectKnowledgePresentation.Summary {
        ProjectKnowledgePresentation.summary(snapshot: currentSnapshot, invocations: invocations)
    }

    private var historyUnavailable: Bool {
        currentSnapshot.tasks.contains {
            model.invocationAvailabilityByTask[AppModel.invocationTaskKey(
                currentSnapshot.projectId, $0.taskId
            )] == "unavailable"
        }
    }

    var body: some View {
        let snapshot = currentSnapshot
        List {
            syncSection
            knowledgeSection(L("Decisions"), values: summary.decisions,
                             empty: L("No decision was reported in this projection."))
            knowledgeSection(L("Past attempts"), values: summary.attempts,
                             empty: historyUnavailable
                                ? L("Could not read this Mesh's invocation history.")
                                : L("No attempt was reported in this projection."))
            if historyUnavailable {
                Section {
                    Button(L("Retry invocation history")) {
                        for task in currentSnapshot.tasks {
                            model.refreshInvocationHistory(
                                projectId: snapshot.projectId, taskId: task.taskId
                            )
                        }
                    }
                }
            }
            knowledgeSection(L("Reported results"), values: summary.results,
                             empty: L("No result was reported in this projection."))
            Section {
                if summary.revisions.isEmpty {
                    Text(L("No verified Git revision was reported for this Mesh."))
                        .font(.caption).foregroundStyle(Theme.muted)
                } else {
                    ForEach(summary.revisions) { revision in
                        NavigationLink {
                            ProjectKnowledgeRevisionView(
                                revision: revision, snapshot: snapshot, model: model
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(revision.name)
                                Text(String(revision.commitSha.prefix(12)))
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
            } header: {
                Text(L("Repository revisions"))
            } footer: {
                Text(L("An observed Git HEAD is evidence of a checkout revision, not a recorded decision or verified Task result."))
            }
            Section {
                if summary.packets.isEmpty {
                    Text(L("No Cortex packet has been reported for this Mesh."))
                        .font(.caption).foregroundStyle(Theme.muted)
                } else {
                    ForEach(summary.packets) { integration in
                        NavigationLink {
                            ProjectCortexEndpointView(
                                projectId: snapshot.projectId, endpointId: integration.endpointId,
                                integration: integration, model: model
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(integration.endpointId)
                                if let packet = integration.packet {
                                    Text(String(format: L("%d evidence selected · %d omitted"),
                                                packet.included, packet.omitted))
                                        .font(.caption).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text(L("Prepared context packets"))
            } footer: {
                Text(L("A prepared packet does not prove that an agent received or used it."))
            }
        }
        .pageNavigationTitle(L("Knowledge")) {
            Button { showingDecisionEditor = true } label: {
                Image(systemName: "plus")
            }
            .disabled(snapshot.tasks.isEmpty)
            .accessibilityLabel(L("Record decision"))
        }
        .sheet(isPresented: $showingDecisionEditor) {
            KnowledgeDecisionEditor(snapshot: currentSnapshot, model: model)
        }
        .refreshable { await sync.refresh(projectId: snapshot.projectId, model: model) }
        .task(id: connectionKey) {
            await sync.refresh(projectId: snapshot.projectId, model: model)
        }
    }

    var connectionKey: String {
        let rooms = (model.meshProjectSourceRooms[snapshot.projectId] ?? []).sorted().map { room in
            "\(room):\(model.roomRuntime[room]?.socketUp == true)"
        }.joined(separator: "|")
        #if targetEnvironment(macCatalyst)
        return "\(snapshot.projectId):\(rooms):\(model.localMCPReader?.isReady == true)"
        #else
        return "\(snapshot.projectId):\(rooms)"
        #endif
    }

    private var syncSection: some View {
        Section {
            CompatLabeledContent(L("Source"), value: L("Mesh Memory, events, Task capsules and observed calls"))
            CompatLabeledContent(L("Snapshot generated"), value: ReportBuilder.stamp(currentSnapshot.generatedAt))
            HStack(spacing: 10) {
                if sync.state == .loading { ProgressView() }
                Text(syncTitle).font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                Button {
                    Task { await sync.refresh(projectId: snapshot.projectId, model: model) }
                } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(sync.state == .loading)
                    .accessibilityLabel(L("Refresh knowledge"))
                    .accessibilityIdentifier("knowledge.refresh")
            }
        } footer: {
            Text(L("Decisions are recorded explicitly. Agent reports and observed calls appear when supplied by the computer. Missing records do not prove the Mesh has no history."))
        }
    }

    private var syncTitle: String {
        switch sync.state {
        case .saved: return L("Saved evidence")
        case .loading: return L("Refreshing knowledge…")
        case .updated: return L("Evidence refreshed")
        case .unavailable: return L("Could not refresh. Saved evidence is still available.")
        }
    }

    private func knowledgeSection(
        _ title: String, values: [ProjectKnowledgePresentation.Entry], empty: String
    ) -> some View {
        Section(title) {
            if values.isEmpty {
                Text(empty).font(.caption).foregroundStyle(Theme.muted)
            } else {
                ForEach(values) { entry in
                    NavigationLink {
                        ProjectKnowledgeEntryView(entry: entry, snapshot: currentSnapshot, model: model)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.text).lineLimit(3)
                            Text([entry.source, entry.commitSha.map { String($0.prefix(12)) }]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
        }
    }
}

struct ProjectKnowledgeRevisionView: View {
    let revision: ProjectKnowledgePresentation.Revision
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel

    var body: some View {
        List {
            Section(L("Observed checkout")) {
                CompatLabeledContent(L("Repository"), value: revision.repositoryId)
                Text(revision.commitSha).textSelection(.enabled)
            }
            if revision.hasGraph {
                NavigationLink(L("Open repository graph")) {
                    ProjectGraphView(snapshot: snapshot, model: model)
                }
            }
        }
        .pageNavigationTitle(L("Revision"))
    }
}

struct ProjectKnowledgeEntryView: View {
    let entry: ProjectKnowledgePresentation.Entry
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @State private var showingCorrection = false

    private var durableDecision: ProjectKnowledgeRecord? {
        (snapshot.knowledge ?? []).first {
            entry.id == "memory:\($0.id)" && $0.category == "decision"
        }
    }

    var body: some View {
        List {
            Section(L("Evidence")) {
                Text(entry.text)
                CompatLabeledContent(L("Source"), value: entry.source)
                if let repositoryId = entry.repositoryId {
                    CompatLabeledContent(L("Repository"), value: repositoryId)
                }
                if let commitSha = entry.commitSha {
                    CompatLabeledContent(L("Commit"), value: commitSha)
                        .textSelection(.enabled)
                }
                if let revision = entry.revision {
                    CompatLabeledContent(L("Observed revision"), value: revision)
                }
            }
            Section(L("Related work")) {
                NavigationLink(L("Open Task")) {
                    TaskRouteView(
                        route: .init(projectId: snapshot.projectId, taskId: entry.taskId),
                        model: model, onOpenSession: { _ in }, presentedAsSheet: false
                    )
                }
                if entry.hasGraph {
                    NavigationLink(L("Open repository graph")) {
                        ProjectGraphView(snapshot: snapshot, model: model)
                    }
                }
            }
            if durableDecision != nil {
                Section {
                    Button(L("Correct or withdraw decision")) { showingCorrection = true }
                }
            }
        }
        .pageNavigationTitle(L("Knowledge"))
        .sheet(isPresented: $showingCorrection) {
            KnowledgeDecisionEditor(snapshot: snapshot, model: model,
                                    superseded: durableDecision)
        }
    }
}
