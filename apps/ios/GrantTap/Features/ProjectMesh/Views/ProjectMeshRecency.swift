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
        var sessionById: [String: SessionInfo] = [:]
        for session in sessions where sessionById[session.sessionId] == nil {
            sessionById[session.sessionId] = session
        }
        let executionsByTask = Dictionary(grouping: snapshot.executions, by: \.taskId)
        return tasks.map { task in
            let executions = executionsByTask[task.taskId] ?? []
            let owner = executions.first { $0.sessionId == task.ownerSessionId }
            let current = owner.flatMap { sessionById[$0.sessionId] }
            let seen = executions.reduce(task.updatedAt) { latest, execution in
                max(max(latest, execution.lastSeenAt),
                    sessionById[execution.sessionId]?.lastActivityAt ?? 0)
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
