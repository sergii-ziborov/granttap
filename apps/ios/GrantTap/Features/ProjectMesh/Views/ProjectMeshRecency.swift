import Foundation

/// A Task's current row, prepared once for the whole list.
enum ProjectMeshRecency {
    struct Row {
        let task: ProjectMeshTask
        let execution: ExecutionSessionLink?
        let session: SessionInfo?
        let state: String
        let lastActiveAt: Double
    }

    static func rows(
        _ tasks: [ProjectMeshTask], snapshot: ProjectMeshSnapshot, sessions: [SessionInfo]
    ) -> [Row] {
        let sessionsByIdentity = Dictionary(grouping: sessions) { "\($0.agent)\u{1f}\($0.sessionId)" }
        let executionsByIdentity = Dictionary(grouping: snapshot.executions) { "\($0.provider)\u{1f}\($0.sessionId)" }
        func observed(_ execution: ExecutionSessionLink) -> SessionInfo? {
            let key = "\(execution.provider)\u{1f}\(execution.sessionId)"
            let unambiguous = Set((executionsByIdentity[key] ?? []).map(\.computerId)).count == 1
            return sessionsByIdentity[key]?.filter {
                ($0.projectId == nil || $0.projectId == snapshot.projectId)
                    && ($0.taskId == nil || $0.taskId == execution.taskId)
                    && ($0.computerId == execution.computerId || ($0.computerId == nil && unambiguous))
            }.max { $0.lastActivityAt < $1.lastActivityAt }
        }
        let executionsByTask = Dictionary(grouping: snapshot.executions, by: \.taskId)
        return tasks.map { task in
            let executions = executionsByTask[task.taskId] ?? []
            let owner = executions.filter { $0.sessionId == task.ownerSessionId }.max {
                if ($0.endedAt == nil) != ($1.endedAt == nil) { return $0.endedAt != nil }
                return $0.lastSeenAt < $1.lastSeenAt
            }
            let current = owner.flatMap(observed)
            let seen = executions.reduce(task.updatedAt) { latest, execution in
                max(max(latest, execution.lastSeenAt),
                    observed(execution)?.lastActivityAt ?? 0)
            }
            return Row(
                task: task, execution: owner, session: current,
                state: ProjectMeshTaskPresentation.state(
                    task: task, execution: owner, currentSession: current
                ),
                lastActiveAt: seen
            )
        }.sorted { left, right in
            if left.lastActiveAt != right.lastActiveAt {
                return left.lastActiveAt > right.lastActiveAt
            }
            return left.task.taskId < right.task.taskId
        }
    }

    static func lastActiveAt(
        _ task: ProjectMeshTask, snapshot: ProjectMeshSnapshot, sessions: [SessionInfo]
    ) -> Double {
        rows([task], snapshot: snapshot, sessions: sessions).first?.lastActiveAt
            ?? task.updatedAt
    }

    static func ordered(
        _ tasks: [ProjectMeshTask], snapshot: ProjectMeshSnapshot, sessions: [SessionInfo]
    ) -> [ProjectMeshTask] {
        rows(tasks, snapshot: snapshot, sessions: sessions).map(\.task)
    }
}
