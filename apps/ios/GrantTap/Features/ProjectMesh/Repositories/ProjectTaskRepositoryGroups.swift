import Foundation

/// Repository observations partition a workspace's Tasks without changing
/// their durable Project, identity, history, or access scope.
enum ProjectTaskRepositoryGroups {
    struct Assignment {
        let repositoryIds: [String]
        let isCurrent: Bool
    }
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
        let reports = Dictionary(grouping: (snapshot.repositoryDetails ?? []).filter {
            $0.projectId == snapshot.projectId
        }, by: \.id).values.compactMap { $0.max { $0.observedAt < $1.observedAt } }
        confirmed.formUnion(reports.filter { $0.status == "ready" }.map(\.repositoryId))
        confirmed.formUnion(executions.filter { $0.worktree?.isEmpty == false }.compactMap(\.repositoryId))
        let observed = [snapshot.project.canonicalRepositoryId]
            + bindings.map(\.repositoryId) + executions.compactMap(\.repositoryId)
        confirmed.formUnion(observed.filter { !$0.isEmpty && !$0.hasPrefix("local:") })
        return confirmed.filter { !$0.isEmpty }
    }

    static func make(snapshot: ProjectMeshSnapshot, sessions: [SessionInfo],
                     placedRows: [ProjectMeshRecency.Row]? = nil,
                     sourceSnapshots: [String: ProjectMeshSnapshot] = [:]) -> [Group] {
        let rows = placedRows ?? ProjectMeshRecency.rows(
            snapshot.tasks.filter { $0.projectId == snapshot.projectId }, snapshot: snapshot, sessions: sessions
        )
        let grouped = Dictionary(grouping: rows) { row in
            let source = sourceSnapshots[row.task.projectId] ?? snapshot
            return scope(task: row.task, executions: source.executions.filter { $0.taskId == row.task.taskId },
                         confirmed: confirmedRepositories(source))
        }
        return grouped.map { scope, rows in
            switch scope {
            case .repository(let repository):
                return Group(id: repository, repositoryId: repository,
                             title: ProjectOtherSide.displayName(of: repository, in: snapshot), rows: rows)
            case .multiple:
                return Group(id: "multiple", repositoryId: nil, title: L("Multiple repositories"), rows: rows)
            case .workspace:
                return Group(id: "workspace", repositoryId: nil,
                             title: isWorkspace(snapshot) ? L("Workspace tasks") : L("No repository reported"), rows: rows)
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
        let assignment = assignment(task: task, executions: executions, confirmed: confirmed)
        if assignment.repositoryIds.count == 1, let repository = assignment.repositoryIds.first {
            return .repository(repository)
        }
        return assignment.repositoryIds.isEmpty ? .workspace : .multiple
    }

    static func assignment(task: ProjectMeshTask, snapshot: ProjectMeshSnapshot) -> Assignment {
        guard task.projectId == snapshot.projectId else {
            return Assignment(repositoryIds: [], isCurrent: false)
        }
        return assignment(task: task, executions: snapshot.executions.filter { $0.taskId == task.taskId },
                          confirmed: confirmedRepositories(snapshot))
    }

    static func assignments(_ snapshot: ProjectMeshSnapshot) -> [String: Assignment] {
        let confirmed = confirmedRepositories(snapshot)
        let executions = Dictionary(grouping: snapshot.executions, by: \.taskId)
        return Dictionary(uniqueKeysWithValues: snapshot.tasks.filter { $0.projectId == snapshot.projectId }.map {
            ($0.taskId, assignment(task: $0, executions: executions[$0.taskId] ?? [], confirmed: confirmed))
        })
    }

    private static func assignment(
        task: ProjectMeshTask, executions: [ExecutionSessionLink], confirmed: Set<String>
    ) -> Assignment {
        let owner = executions.filter { $0.sessionId == task.ownerSessionId }
        let activeOwner = owner.filter { $0.endedAt == nil }
        let current = repositories(activeOwner.isEmpty ? owner : activeOwner, confirmed: confirmed)
        if !current.isEmpty { return Assignment(repositoryIds: current.sorted(), isCurrent: true) }
        let history = repositories(executions, confirmed: confirmed)
        return Assignment(repositoryIds: history.sorted(), isCurrent: false)
    }

    private static func repositories(
        _ executions: [ExecutionSessionLink], confirmed: Set<String>
    ) -> Set<String> {
        Set(executions.compactMap(\.repositoryId).filter(confirmed.contains))
    }
}
