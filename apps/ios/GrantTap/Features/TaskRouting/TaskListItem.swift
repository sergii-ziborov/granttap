import Foundation

enum TaskListDestination: Equatable {
    case task(TaskRoute)
    case session(String)
}

/// One user-visible Task assembled from Mesh state first, with legacy native
/// sessions added only when they do not belong to a known Mesh Task.
struct TaskListItem: Identifiable, Equatable {
    let id: String
    let destination: TaskListDestination
    let projectId: String?
    let taskId: String?
    let projectName: String
    let title: String
    let summary: String?
    let state: String
    let ownerExecution: ExecutionSessionLink?
    let currentSession: SessionInfo?
    let historicalExecutions: [ExecutionSessionLink]
    let sessionIds: [String]
    let lastActivityAt: Double

    var ownerProvider: String { ownerExecution?.provider ?? currentSession?.agent ?? "granttap" }
    var isTerminal: Bool {
        ["completed", "finished", "failed", "cancelled"].contains(state)
    }
    var ownerName: String {
        ownerExecution.map(MeshActorPresentation.executionName)
            ?? currentSession.map { AgentIdentity.displayName($0.agent) }
            ?? L("Unassigned")
    }

    /// Seconds since this task last did anything, from any of its executions.
    func idleSeconds(nowMs: Double = Date().timeIntervalSince1970 * 1_000) -> Int {
        Int(max(0, (nowMs - lastActivityAt) / 1_000))
    }

    /// Whether any execution of this task is still open on some computer.
    ///
    /// A task keeps its last published state, so a session that ended without
    /// saying so leaves "working" behind. That state is only believable while an
    /// execution is actually open, or a live session is present.
    var hasOpenExecution: Bool {
        if currentSession != nil && !isTerminal { return true }
        if let owner = ownerExecution, owner.endedAt == nil { return true }
        return historicalExecutions.contains { $0.endedAt == nil }
    }
}

/// What counts as recently closed or inactive work on the first screen.
enum TaskRecency {
    static let recentWindowSeconds = 24 * 60 * 60

    static func isRecent(
        _ item: TaskListItem,
        nowMs: Double = Date().timeIntervalSince1970 * 1_000
    ) -> Bool {
        item.idleSeconds(nowMs: nowMs) <= recentWindowSeconds
    }
}

@MainActor
enum TaskListCatalog {
    static func items(
        model: AppModel, sessions: [SessionInfo], history: Bool = false
    ) -> [TaskListItem] {
        let newestById = Dictionary(grouping: sessions, by: \.sessionId)
            .compactMapValues { $0.max { $0.lastActivityAt < $1.lastActivityAt } }
        var result: [TaskListItem] = []
        var meshKeys = Set<String>()
        for snapshot in model.meshSnapshots.values {
            // A hidden Project's Tasks leave the lists; its chats stay chats.
            if model.isProjectHidden(snapshot.projectId) { continue }
            let projectName = model.projectDisplayName(snapshot)
            for task in snapshot.tasks {
                if shouldHideNestedTask(task, sessions: sessions) { continue }
                let key = meshKey(projectId: snapshot.projectId, taskId: task.taskId)
                meshKeys.insert(key)
                result.append(meshItem(
                    task: task, snapshot: snapshot, sessions: sessions,
                    newestById: newestById, history: history, projectName: projectName
                ))
            }
        }
        result.append(contentsOf: legacyItems(
            sessions: sessions, excluding: meshKeys, history: history
        ))
        return onePerChat(result).sorted { lhs, rhs in
            if lhs.lastActivityAt != rhs.lastActivityAt {
                return lhs.lastActivityAt > rhs.lastActivityAt
            }
            return lhs.id < rhs.id
        }
    }

    private static func meshItem(
        task: ProjectMeshTask,
        snapshot: ProjectMeshSnapshot,
        sessions: [SessionInfo],
        newestById: [String: SessionInfo],
        history: Bool,
        projectName: String? = nil
    ) -> TaskListItem {
        let executions = snapshot.executions.filter { $0.taskId == task.taskId }
        let ownerId = task.ownerSessionId.map { AppModel.rootSessionId($0, in: sessions) }
        let owner = ownerId.flatMap { id in executions.first { $0.sessionId == id } }
            ?? task.ownerSessionId.flatMap { id in executions.first { $0.sessionId == id } }
        let taskSessions = sessions.filter {
            $0.projectId == snapshot.projectId && $0.taskId == task.taskId
        }
        let fallback = taskSessions.max { $0.lastActivityAt < $1.lastActivityAt }
        let current = ownerId.flatMap { newestById[$0] }
            ?? task.ownerSessionId.flatMap { newestById[$0] }
            ?? (task.ownerSessionId == nil ? fallback : nil)
        let ids = Set(
            (executions.map(\.sessionId) + taskSessions.map(\.sessionId) + [ownerId].compactMap { $0 })
                .map { AppModel.rootSessionId($0, in: sessions) }
                .filter { !AppModel.isNestedCursorSession($0) }
        ).sorted()
        let activity = max(
            task.updatedAt,
            max(current?.lastActivityAt ?? 0, fallback?.lastActivityAt ?? 0)
        )
        let state = current.map { history ? historyState($0.state) : $0.state } ?? task.state
        return TaskListItem(
            id: "task:\(snapshot.projectId)\u{1f}\(task.taskId)",
            destination: .task(.init(projectId: snapshot.projectId, taskId: task.taskId)),
            projectId: snapshot.projectId, taskId: task.taskId,
            projectName: projectName ?? snapshot.project.name, title: nativeTitle(current) ?? task.title,
            summary: task.goal.isEmpty ? fallback?.summary : task.goal,
            state: state, ownerExecution: owner,
            currentSession: current, historicalExecutions: executions,
            sessionIds: ids, lastActivityAt: activity
        )
    }

    private static func legacyItems(
        sessions: [SessionInfo], excluding meshKeys: Set<String>, history: Bool
    ) -> [TaskListItem] {
        var representatives: [String: SessionInfo] = [:]
        for session in sessions {
            if AppModel.isNestedCursorSession(session.sessionId) { continue }
            if let projectId = session.projectId, let taskId = session.taskId,
               meshKeys.contains(meshKey(projectId: projectId, taskId: taskId)) { continue }
            let key = session.projectId.flatMap { project in
                session.taskId.map { meshKey(projectId: project, taskId: $0) }
            } ?? "session:\(session.sessionId)"
            if representatives[key].map({ $0.lastActivityAt >= session.lastActivityAt }) == true {
                continue
            }
            representatives[key] = session
        }
        return representatives.values.map { session in
            TaskListItem(
                id: "session:\(session.sessionId)", destination: .session(session.sessionId),
                projectId: session.projectId, taskId: session.taskId,
                projectName: session.projectGroupTitle, title: session.displayTitle,
                summary: session.summary,
                state: history ? historyState(session.state) : session.state,
                ownerExecution: nil,
                currentSession: session, historicalExecutions: [],
                sessionIds: [session.sessionId], lastActivityAt: session.lastActivityAt
            )
        }
    }

    /// A Task-tool clone is the parent chat's work, never its own card.
    private static func shouldHideNestedTask(
        _ task: ProjectMeshTask, sessions: [SessionInfo]
    ) -> Bool {
        guard let owner = task.ownerSessionId else { return false }
        if AppModel.isNestedCursorSession(owner) { return true }
        return sessions.contains { session in
            session.childThreads?.contains { $0.threadId == owner } == true
        }
    }

    /// A chat is one conversation, so it is one card. A Project snapshot kept
    /// from before its identity changed, or a session the Mesh has not claimed,
    /// used to add a second card for the same chat with an older summary.
    static func onePerChat(_ items: [TaskListItem]) -> [TaskListItem] {
        var chosen: [String: TaskListItem] = [:]
        var unattached: [TaskListItem] = []
        for item in items {
            guard let chat = item.currentSession?.sessionId else {
                unattached.append(item)
                continue
            }
            if let existing = chosen[chat], !prefer(item, over: existing) { continue }
            chosen[chat] = item
        }
        return unattached + Array(chosen.values)
    }

    private static func prefer(_ candidate: TaskListItem, over existing: TaskListItem) -> Bool {
        if candidate.lastActivityAt != existing.lastActivityAt {
            return candidate.lastActivityAt > existing.lastActivityAt
        }
        // The Mesh's card knows the Task; the plain session card does not.
        if (candidate.taskId != nil) != (existing.taskId != nil) { return candidate.taskId != nil }
        return candidate.id < existing.id
    }

    private static func meshKey(projectId: String, taskId: String) -> String {
        "\(projectId)\u{1f}\(taskId)"
    }

    private static func historyState(_ state: String) -> String {
        ["failed", "cancelled"].contains(state) ? state : "finished"
    }

    private static func nativeTitle(_ session: SessionInfo?) -> String? {
        guard let session else { return nil }
        let title = session.displayTitle
        return title == L("Untitled chat") ? nil : title
    }
}
