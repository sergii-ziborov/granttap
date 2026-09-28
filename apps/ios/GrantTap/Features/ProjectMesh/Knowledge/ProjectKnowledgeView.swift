import SwiftUI

struct ProjectKnowledgeView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @State private var showingDecisionEditor = false

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
            Section {
                CompatLabeledContent(L("Source"), value: L("Mesh Memory, events, Task capsules and observed calls"))
                CompatLabeledContent(L("Snapshot received"), value: ReportBuilder.stamp(summary.freshness))
            } footer: {
                Text(L("This device holds a bounded projection. Missing records are not proof that the Mesh has no history."))
            }
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
        .onAppear(perform: requestHistory)
        .onChange(of: currentSnapshot.generatedAt) { _ in requestHistory() }
    }

    private func requestHistory() {
        for task in currentSnapshot.tasks {
            let key = AppModel.invocationTaskKey(snapshot.projectId, task.taskId)
            if model.invocationAvailabilityByTask[key] == "unavailable" {
                model.refreshInvocationHistory(projectId: snapshot.projectId, taskId: task.taskId)
            } else {
                model.requestInvocationHistory(projectId: snapshot.projectId, taskId: task.taskId)
            }
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
