import SwiftUI

/// The three doors of a Project — its rules, its members, its Mesh — each
/// with what stands behind it, on the Project screen itself. A "Manage
/// Project" screen that only held these rows was one tap of nothing.
struct ProjectDestinationRows: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel

    var body: some View {
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
                title: L("Mesh status"),
                detail: ProjectManagePresentation.meshSummary(snapshot),
                icon: "point.3.connected.trianglepath.dotted"
            )
        }
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
