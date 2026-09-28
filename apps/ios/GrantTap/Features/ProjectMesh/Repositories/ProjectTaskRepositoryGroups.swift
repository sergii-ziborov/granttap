import Foundation

/// Repository observations partition a workspace's Tasks without changing
/// their durable Project, identity, history, or access scope.
enum ProjectTaskRepositoryGroups {
    struct Group: Identifiable {
        let id: String
        let repositoryId: String?
        let title: String
        let rows: [ProjectMeshRecency.Row]
    }

    private enum Scope: Hashable {
        case repository(String)
        case multiple
        case workspace
    }

    static func isWorkspace(_ snapshot: ProjectMeshSnapshot) -> Bool {
        let own = snapshot.project.canonicalRepositoryId
        return own.hasPrefix("local:") && !confirmedRepositories(snapshot).contains(own)
    }

    static func confirmedRepositories(_ snapshot: ProjectMeshSnapshot) -> Set<String> {
        let taskIDs = Set(snapshot.tasks.filter { $0.projectId == snapshot.projectId }.map(\.taskId))
        let bindings = (snapshot.bindings ?? []).filter { $0.projectId == snapshot.projectId }
        let executions = snapshot.executions.filter { taskIDs.contains($0.taskId) }
        var confirmed = Set(bindings.filter { $0.revision?.isEmpty == false }.map(\.repositoryId))
        confirmed.formUnion(executions.filter { $0.worktree?.isEmpty == false }.compactMap(\.repositoryId))
        let observed = [snapshot.project.canonicalRepositoryId]
            + bindings.map(\.repositoryId) + executions.compactMap(\.repositoryId)
        confirmed.formUnion(observed.filter { !$0.isEmpty && !$0.hasPrefix("local:") })
        return confirmed.filter { !$0.isEmpty }
    }

    static func make(snapshot: ProjectMeshSnapshot, sessions: [SessionInfo]) -> [Group] {
        let rows = ProjectMeshRecency.rows(
            snapshot.tasks.filter { $0.projectId == snapshot.projectId }, snapshot: snapshot, sessions: sessions
        )
        guard isWorkspace(snapshot) else {
            return [Group(id: "tasks", repositoryId: nil, title: L("Tasks"), rows: rows)]
        }
        let confirmed = confirmedRepositories(snapshot)
        let executions = Dictionary(grouping: snapshot.executions, by: \.taskId)
        let grouped = Dictionary(grouping: rows) { row in
            scope(task: row.task, executions: executions[row.task.taskId] ?? [], confirmed: confirmed)
        }
        return grouped.map { scope, rows in
            switch scope {
            case .repository(let repository):
                return Group(id: repository, repositoryId: repository,
                             title: ProjectOtherSide.displayName(of: repository, in: snapshot), rows: rows)
            case .multiple:
                return Group(id: "multiple", repositoryId: nil, title: L("Multiple repositories"), rows: rows)
            case .workspace:
                return Group(id: "workspace", repositoryId: nil, title: L("Workspace tasks"), rows: rows)
            }
        }.sorted { left, right in
            if (left.repositoryId != nil) != (right.repositoryId != nil) { return left.repositoryId != nil }
            if left.repositoryId == nil { return left.id < right.id }
            return left.title == right.title ? left.id < right.id : left.title < right.title
        }
    }

    private static func scope(
        task: ProjectMeshTask, executions: [ExecutionSessionLink], confirmed: Set<String>
    ) -> Scope {
        let owner = executions.filter { $0.sessionId == task.ownerSessionId }
        let activeOwner = owner.filter { $0.endedAt == nil }
        let current = repositories(activeOwner.isEmpty ? owner : activeOwner, confirmed: confirmed)
        if current.count == 1, let repository = current.first { return .repository(repository) }
        let history = repositories(executions, confirmed: confirmed)
        if history.count == 1, let repository = history.first { return .repository(repository) }
        return history.isEmpty ? .workspace : .multiple
    }

    private static func repositories(
        _ executions: [ExecutionSessionLink], confirmed: Set<String>
    ) -> Set<String> {
        Set(executions.compactMap(\.repositoryId).filter(confirmed.contains))
    }
}
