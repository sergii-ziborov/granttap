import SwiftUI

/// Both Mac and iPad recompute the same repository sections from the latest
/// snapshot. Every navigation route retains the Task's original Mesh scope.
struct ProjectRepositoryTaskSections: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    var onOpenSession: (SessionInfo) -> Void = { _ in }

    var body: some View {
        let groups = ProjectTaskRepositoryGroups.make(snapshot: snapshot, sessions: model.sessions)
        ForEach(groups) { group in
            Section {
                ForEach(group.rows, id: \.task.taskId) { row in
                    NavigationLink {
                        TaskRouteView(
                            route: .init(projectId: row.task.projectId, taskId: row.task.taskId),
                            model: model, onOpenSession: onOpenSession,
                            presentedAsSheet: false
                        )
                    } label: {
                        ProjectMeshTaskRow(
                            task: row.task, execution: row.execution, currentSession: row.session,
                            presentedState: row.state, lastActiveAt: row.lastActiveAt
                        )
                    }
                    .accessibilityIdentifier("project.task.\(row.task.taskId)")
                }
            } header: {
                Text(group.title)
            } footer: {
                if !group.rows.isEmpty {
                    Text(L("Most recently worked first."))
                }
            }
            .accessibilityIdentifier("project.task-group.\(group.id)")
        }
    }
}
