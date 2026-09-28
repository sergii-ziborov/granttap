import SwiftUI

/// The three doors of a Project — its rules, its members, its Mesh — each
/// with what stands behind it, on the Project screen itself. A "Manage
/// Project" screen that only held these rows was one tap of nothing.
struct ProjectDestinationRows: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationLink {
            ProjectKnowledgeView(snapshot: snapshot, model: model)
        } label: {
            ProjectDestinationLabel(
                title: L("Knowledge"), detail: L("Decisions, attempts and context evidence"),
                icon: "book"
            )
        }
        .accessibilityIdentifier("project.knowledge")
        NavigationLink {
            ProjectCapabilitiesView(snapshot: snapshot, model: model)
        } label: {
            ProjectDestinationLabel(
                title: L("Tools & Skills"), detail: L("Catalog, requests and endpoint availability"),
                icon: "wrench.and.screwdriver"
            )
        }
        .accessibilityIdentifier("project.tools-skills")
        NavigationLink {
            ProjectExecutionView(snapshot: snapshot, model: model)
        } label: {
            ProjectDestinationLabel(
                title: L("Execution"), detail: executionDetail, icon: "desktopcomputer"
            )
        }
        .accessibilityIdentifier("project.execution")
        NavigationLink {
            ProjectAutoAcceptView(snapshot: snapshot, model: model)
        } label: {
            ProjectDestinationLabel(
                title: L("Auto-accept"),
                detail: AutoAcceptLevel.parse(model.desiredProjectAutoAcceptLevel(
                    projectId: snapshot.projectId
                )).title,
                icon: "checkmark.circle"
            )
        }
        .accessibilityIdentifier("project.auto-accept")
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
            ProjectRestrictionsView(snapshot: snapshot, model: model)
        } label: {
            ProjectDestinationLabel(
                title: L("Restrictions"),
                detail: snapshot.restrictions.map { LPlural($0.rules.count, one: "%d rule", many: "%d rules") }
                    ?? L("No rules reported"),
                icon: "ruler"
            )
        }
        .accessibilityIdentifier("project.restrictions")
        NavigationLink {
            ProjectEnvironmentView(snapshot: snapshot, model: model)
        } label: {
            ProjectDestinationLabel(
                title: L("Environment variables"),
                detail: snapshot.environment.map {
                    LPlural($0.variables.count, one: "%d variable", many: "%d variables")
                } ?? L("No values reported"),
                icon: "key"
            )
        }
        .accessibilityIdentifier("project.environment")
        NavigationLink {
            ProjectMembersView(snapshot: snapshot, model: model)
        } label: {
            ProjectDestinationLabel(
                title: L("Members / Computers"),
                detail: ProjectManagePresentation.membersSummary(snapshot),
                icon: "person.2"
            )
        }
        .accessibilityIdentifier("project.members")
        NavigationLink {
            ProjectGraphView(snapshot: snapshot, model: model)
        } label: {
            ProjectDestinationLabel(
                title: L("Graph"),
                detail: L("Weavatrix components and evidenced relations"),
                icon: "point.3.connected.trianglepath.dotted"
            )
        }
        .accessibilityIdentifier("project.openGraph")
        NavigationLink {
            ProjectMeshStatisticsView(snapshot: snapshot, model: model)
        } label: {
            ProjectDestinationLabel(
                title: L("Statistics"),
                detail: L("Mesh work, graph and imported data"),
                icon: "chart.bar.xaxis"
            )
        }
        .accessibilityIdentifier("project.statistics")
        NavigationLink {
            ProjectCortexView(snapshot: snapshot, model: model)
        } label: {
            ProjectDestinationLabel(
                title: L("Cortex Loom"),
                detail: L("Context graphs, execution quality and token statistics"),
                icon: "brain.head.profile"
            )
        }
        .accessibilityIdentifier("project.cortex")
        NavigationLink {
            ProjectMeshStatusView(snapshot: snapshot, model: model)
        } label: {
            ProjectDestinationLabel(
                title: L("Health"),
                detail: ProjectManagePresentation.meshSummary(snapshot),
                icon: "heart.text.square"
            )
        }
        .accessibilityIdentifier("project.health")
    }

    private var executionDetail: String {
        let policy = model.projectGovernance[snapshot.projectId]?.policy?.execution ?? snapshot.execution
        if let endpoint = policy?.targetEndpointId { return String(format: L("Pinned to %@"), endpoint) }
        return L("Choose an allowed Mesh computer for each new Task")
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
