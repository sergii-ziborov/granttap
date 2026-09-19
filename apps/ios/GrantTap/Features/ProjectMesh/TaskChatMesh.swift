import Foundation

/// The section can be present while the root timeline is empty. It must stay
/// folded: opening every conversation dumped GrantTap's own chat under 22 runs.
enum TaskChatTranscriptPresentation {
    static func showsEmptyPlaceholder(timelineEmpty: Bool, threadCount: Int) -> Bool {
        timelineEmpty && threadCount == 0
    }

    static func showsAgentConversations(threadCount: Int) -> Bool {
        threadCount > 0
    }

    static func threadsOpen(userExpanded: Bool, focusedThread: Bool) -> Bool {
        userExpanded || focusedThread
    }
}

extension TaskChatView {
    var childThreads: [ChildThreadDisplayRow] {
        ChildThreadTree.rows(
            rootId: chatSessionId,
            threads: currentSession.childThreads ?? [],
            activity: entries
        )
    }

    var projectMeshSnapshot: ProjectMeshSnapshot? {
        model.meshSnapshot(for: currentSession.projectId)
    }

    var taskExecutionSessionIds: [String] {
        guard let taskId = currentSession.taskId else { return [chatSessionId] }
        let linked = projectMeshSnapshot?.executions
            .filter { $0.taskId == taskId }.map(\.sessionId) ?? []
        // The chat you opened is always a source of its own transcript.
        // Replacing it with the Task's executions meant a stale or split Task
        // pointed the timeline at other sessions entirely, and a chat with
        // messages sitting on this phone rendered as "no messages loaded".
        return linked.contains(chatSessionId) ? linked : linked + [chatSessionId]
    }

    var taskActivityEntries: [ActivityEntry] {
        var byId: [String: ActivityEntry] = [:]
        for sessionId in taskExecutionSessionIds {
            for entry in model.activities[sessionId]?.entries ?? [] where entry.childThreadId == nil {
                byId[entry.id] = entry
            }
        }
        if byId.isEmpty {
            for entry in rootEntries { byId[entry.id] = entry }
        }
        return byId.values.sorted { $0.createdAt < $1.createdAt }
    }

    var combinedTimeline: [CombinedTaskTimelineItem] {
        let activity = taskActivityEntries.map(CombinedTaskTimelineItem.activity)
        let mesh = model.meshEvents(forTaskId: currentSession.taskId)
            .map(CombinedTaskTimelineItem.mesh)
        return (activity + mesh).sorted { $0.createdAt < $1.createdAt }
    }
}
