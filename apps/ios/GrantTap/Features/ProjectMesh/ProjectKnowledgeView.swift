import SwiftUI

/// Decisions, past attempts, and the context a Task Capsule already carries.
/// Empty is allowed: the screen says so rather than inferring a journal.
struct ProjectKnowledgeView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel

    var invocations: [ProjectInvocationRecord] {
        ProjectKnowledgePresentation.invocations(
            from: model.invocationHistoryByTask,
            projectId: snapshot.projectId,
            taskIds: snapshot.tasks.map(\.taskId)
        )
    }

    var summary: ProjectKnowledgePresentation.Summary {
        ProjectKnowledgePresentation.summary(snapshot: snapshot, invocations: invocations)
    }

    var body: some View {
        List {
            Section {
                CompatLabeledContent(L("Source"), value: summary.source ?? L("Project snapshot"))
                if let freshness = summary.freshnessLine {
                    CompatLabeledContent(L("Freshness"), value: freshness)
                }
            } footer: {
                Text(L("What context the agent gets comes from Task Capsules and observed runtime history. The phone does not invent a journal."))
            }
            Section {
                if summary.decisions.isEmpty {
                    Text(L("No decisions recorded yet."))
                        .font(.caption).foregroundStyle(Theme.muted)
                } else {
                    ForEach(Array(summary.decisions.enumerated()), id: \.offset) { _, text in
                        Text(text)
                    }
                }
            } header: {
                Text(L("Decisions"))
            }
            Section {
                if summary.attempts.isEmpty {
                    Text(L("No past attempts recorded yet."))
                        .font(.caption).foregroundStyle(Theme.muted)
                } else {
                    ForEach(Array(summary.attempts.enumerated()), id: \.offset) { _, text in
                        Text(text).font(.caption)
                    }
                }
            } header: {
                Text(L("Past attempts"))
            } footer: {
                Text(L("Attempts come from runtime history and blocked or failed Mesh events."))
            }
            Section {
                if summary.agentContext.isEmpty {
                    Text(L("No agent context has been published yet."))
                        .font(.caption).foregroundStyle(Theme.muted)
                } else {
                    ForEach(Array(summary.agentContext.enumerated()), id: \.offset) { _, text in
                        Text(text)
                    }
                }
            } header: {
                Text(L("What context the agent gets"))
            }
        }
        .navigationTitle(L("Knowledge"))
        .onAppear {
            for task in snapshot.tasks {
                model.requestInvocationHistory(projectId: snapshot.projectId, taskId: task.taskId)
            }
        }
    }
}
