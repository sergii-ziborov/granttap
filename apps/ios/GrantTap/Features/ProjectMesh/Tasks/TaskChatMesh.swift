import Foundation

extension TaskChatView {
    func openMesh() {
        #if targetEnvironment(macCatalyst)
        guard let projectId = meshProjectId else { return }
        (onOpenMesh ?? mainWindowMeshAction)?(projectId, chatSessionId)
        #else
        showProjectMesh = true
        #endif
    }

    var meshProjectId: String? {
        if let projectId = currentSession.projectId { return projectId }
        let sessionIds = Set([session.sessionId, chatSessionId])
        if let linked = model.meshSnapshots.values.first(where: { snapshot in
            snapshot.executions.contains {
                sessionIds.contains($0.sessionId)
                    || sessionIds.contains(model.resolvedSessionId($0.sessionId))
            }
        }) { return linked.projectId }
        guard let cwd = currentSession.cwd?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cwd.isEmpty else { return nil }
        return model.meshSnapshots.values.first { snapshot in
            let roots = [snapshot.project.repositoryRoot]
                + (snapshot.bindings ?? []).map(\.localPathHint)
            return roots.compactMap { $0 }.contains {
                cwd == $0 || cwd.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/")
            }
        }?.projectId
    }

    var childThreads: [ChildThreadDisplayRow] {
        ChildThreadTree.rows(
            rootId: chatSessionId,
            threads: currentSession.childThreads ?? [],
            activity: entries
        )
    }

    var projectMeshSnapshot: ProjectMeshSnapshot? {
        model.meshSnapshot(for: meshProjectId)
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
        var ranks: [String: Int] = [:]
        for sessionId in taskExecutionSessionIds {
            for entry in model.activities[sessionId]?.entries ?? [] where entry.childThreadId == nil {
                if ranks[entry.id] == nil { ranks[entry.id] = ranks.count }
                byId[entry.id] = entry
            }
        }
        if byId.isEmpty {
            for entry in rootEntries {
                if ranks[entry.id] == nil { ranks[entry.id] = ranks.count }
                byId[entry.id] = entry
            }
        }
        return byId.values.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return (ranks[$0.id] ?? 0) < (ranks[$1.id] ?? 0)
        }
    }

    var combinedTimeline: [CombinedTaskTimelineItem] {
        let activity = taskActivityEntries.map(CombinedTaskTimelineItem.activity)
        let mesh = model.meshEvents(forTaskId: currentSession.taskId)
            .map(CombinedTaskTimelineItem.mesh)
        return (activity + mesh).sorted { $0.createdAt < $1.createdAt }
    }
}
