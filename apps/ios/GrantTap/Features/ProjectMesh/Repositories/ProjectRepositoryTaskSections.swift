import SwiftUI

/// Mac, iPhone and iPad recompute the same repository sections from the latest
/// snapshot. Every navigation route retains the Task's original Mesh scope.
struct ProjectRepositoryTaskSections: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    var onOpenSession: (SessionInfo) -> Void = { _ in }

    var body: some View {
        let groups = ProjectTaskRepositoryGroups.make(snapshot: snapshot, sessions: model.sessions,
            placedRows: model.repositoryPlacedTasks(projectId: snapshot.projectId), sourceSnapshots: model.meshSnapshots)
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
                        VStack(alignment: .leading, spacing: 3) {
                            ProjectMeshTaskRow(
                                task: row.task, execution: row.execution, currentSession: row.session,
                                presentedState: row.state, lastActiveAt: row.lastActiveAt,
                                repositoryContext: RepositoryCatalogPresentation.taskContext(task: row.task,
                                    snapshot: model.meshSnapshots[row.task.projectId] ?? snapshot)
                            )
                            if row.task.projectId != snapshot.projectId,
                               let source = model.projectDisplayName(id: row.task.projectId) {
                                Text(String(format: L("Started in Mesh: %@"), source))
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .accessibilityIdentifier("project.task.\(row.task.taskId)")
                }
            } header: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.title)
                    if let repository = group.repositoryId, !repository.hasPrefix("local:") {
                        Text(repository).font(.caption2)
                    }
                }
            } footer: {
                if !group.rows.isEmpty {
                    Text(L("Most recently worked first."))
                }
            }
            .accessibilityIdentifier("project.task-group.\(group.id)")
        }
        let relocated = MeshTaskPlacement.make(snapshots: model.repositoryVisibleSnapshots, sessions: model.sessions)
            .filter { $0.sourceProjectId == snapshot.projectId && $0.projectId != snapshot.projectId }
        if !relocated.isEmpty {
            Section(L("Tasks in another Mesh")) {
                ForEach(relocated, id: \.row.task.taskId) { placement in
                    if let target = model.meshSnapshots[placement.projectId] {
                        NavigationLink {
                            ProjectMeshView(snapshot: target, model: model, onOpenSession: onOpenSession)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(placement.row.task.title)
                                Text(String(format: L("Mesh: %@"), model.projectDisplayName(target)))
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
            }
        }
    }
}
