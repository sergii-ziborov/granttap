import SwiftUI

/// The doors of a Project — Knowledge, Tools & Skills, rules, members, and
/// Health — each with what stands behind it, on the Project screen itself.
struct ProjectDestinationRows: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel

    var knowledgeDetail: String {
        ProjectKnowledgePresentation.summary(
            snapshot: snapshot,
            invocations: ProjectKnowledgePresentation.invocations(
                from: model.invocationHistoryByTask,
                projectId: snapshot.projectId,
                taskIds: snapshot.tasks.map(\.taskId)
            )
        ).rowDetail
    }

    var toolsDetail: String {
        ProjectToolsSkillsPresentation.catalog(
            snapshot: snapshot,
            sessions: model.sessions + model.allSessionHistory,
            usage: CapabilityUsageStore.shared.events,
            added: model.addedToolItems(for: snapshot.projectId)
        ).rowDetail
    }

    var healthDetail: String {
        ProjectManagePresentation.healthSummary(
            snapshot, usageEvents: CapabilityUsageStore.shared.events
        )
    }

    var body: some View {
        NavigationLink {
            ProjectKnowledgeView(snapshot: snapshot, model: model)
        } label: {
            ProjectDestinationLabel(
                title: L("Knowledge"),
                detail: knowledgeDetail,
                icon: "book"
            )
        }
        .accessibilityIdentifier("project.knowledge")
        NavigationLink {
            ProjectToolsSkillsView(snapshot: snapshot, model: model)
        } label: {
            ProjectDestinationLabel(
                title: L("Tools & Skills"),
                detail: toolsDetail,
                icon: "wrench.and.screwdriver"
            )
        }
        .accessibilityIdentifier("project.tools-skills")
        NavigationLink {
            ProjectExecutionView(snapshot: snapshot, model: model)
        } label: {
            ProjectDestinationLabel(
                title: L("Execution"),
                detail: ProjectManagePresentation.executionSummary(
                    snapshot, governance: model.projectGovernance[snapshot.projectId]
                ),
                icon: "desktopcomputer"
            )
        }
        .accessibilityIdentifier("project.execution")
        NavigationLink {
            ProjectGovernanceView(project: snapshot.project, model: model)
        } label: {
            ProjectDestinationLabel(
                title: L("Governance"),
                detail: ProjectManagePresentation.governanceSummary(
                    model.projectGovernance[snapshot.projectId],
                    draft: model.projectPolicyDrafts[snapshot.projectId]
                ),
                icon: "checkmark.shield"
            )
        }
        NavigationLink {
            ProjectMembersView(snapshot: snapshot, model: model)
        } label: {
            ProjectDestinationLabel(
                title: L("Members / Computers"),
                detail: ProjectManagePresentation.membersSummary(snapshot),
                icon: "person.2"
            )
        }
        NavigationLink {
            ProjectMeshStatusView(snapshot: snapshot, model: model)
        } label: {
            ProjectDestinationLabel(
                title: L("Health / Graph"),
                detail: healthDetail,
                icon: "point.3.connected.trianglepath.dotted"
            )
        }
        .accessibilityIdentifier("project.health")
    }
}

struct ProjectDestinationLabel: View {
    let title: String
    let detail: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 24).foregroundColor(Theme.codex)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).foregroundColor(Theme.ink)
                Text(detail).font(.caption).foregroundColor(Theme.muted)
            }
        }
        .padding(.vertical, 3)
    }
}
