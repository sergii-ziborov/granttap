#if targetEnvironment(macCatalyst)
import Foundation

/// Adapts local MCP observations to the same Mesh and Task models used by iOS.
/// It never writes them to the phone's encrypted relay persistence.
@MainActor
enum MacLocalProjection {
    static func apply(_ snapshots: [String: ProjectMeshSnapshot], to model: AppModel,
                      sessionUsage: [String: SessionUsageSnapshot]? = nil) {
        let local = Dictionary(uniqueKeysWithValues: snapshots.map { id, fresh in
            (id, retainingEnrichment(fresh, from: model.meshSnapshots[id]))
        })
        let linked = Set(model.connectionRegistry.connections.map(\.id))
        let remoteProjects = Set(model.meshProjectSourceRooms.compactMap { id, rooms in
            rooms.intersection(linked).isEmpty ? nil : id
        })
        model.meshSnapshots = DesktopCatalogSources.snapshots(local: local,
            current: model.meshSnapshots, previousLocalIds: model.localMeshProjectIds,
            remoteProjectIds: remoteProjects, nowMs: Date().timeIntervalSince1970 * 1_000)
        model.localMeshProjectIds = Set(snapshots.keys)
        let executions = snapshots.values.flatMap(\.executions)
        let usageBySession = sessionUsage ?? model.localMCPReader?.sessionUsage ?? [:]
        let endpointId = model.localMCPReader?.status?.endpointId
        let observed = model.localMCPReader?.liveCatalog?.observations(
            endpointId: endpointId, nowMs: Date().timeIntervalSince1970 * 1_000) ?? []
        let tasks = Dictionary(grouping: snapshots.values.flatMap(\.tasks), by: \.taskId)
        var liveNativeIds = Set<String>()
        let sessions = executions.map { execution -> SessionInfo in
            let task = tasks[execution.taskId]?.count == 1 ? tasks[execution.taskId]?.first : nil
            if let native = MacLiveSessionProjection.session(execution: execution, task: task,
                observed: observed, endpointId: endpointId) {
                liveNativeIds.insert(native.sessionId)
                return native
            }
            let last = execution.activeAt ?? execution.updatedAt ?? execution.startedAt
            let recent = execution.endedAt == nil
                && abs(Date().timeIntervalSince1970 * 1_000 - last) < 15 * 60 * 1_000
            let session = SessionInfo(
                sessionId: execution.sessionId, agent: execution.provider,
                projectId: task?.projectId, taskId: execution.taskId,
                computerId: execution.computerId, title: task?.title,
                cwd: execution.workspace, branch: execution.branch,
                worktree: execution.worktree,
                state: execution.endedAt != nil ? "finished" : recent ? "working" : "idle",
                startedAt: execution.startedAt, lastActivityAt: last,
                tokensSession: 0, tokensLastTurn: 0
            )
            guard execution.computerId == model.localMCPReader?.status?.endpointId,
                  let usage = usageBySession[
                    "\(execution.provider)\u{1f}\(execution.sessionId)"] else { return session }
            return usage.applying(to: session)
        }
        let remoteIds = Set(model.sessionSourceRooms.compactMap { id, rooms in
            Set(rooms).intersection(linked).isEmpty ? nil : id
        })
        let cachedRooms = Set(model.macRemoteCatalogs.keys).intersection(linked)
        let cached = cachedRooms.sorted().compactMap { model.macRemoteCatalogs[$0] }
        let remoteLive = AppModel.deduplicatedSessions(cached.flatMap(\.sessions))
        let remoteHistory = AppModel.deduplicatedSessions(cached.flatMap { $0.history ?? [] })
        func awaitingReport(_ item: SessionInfo) -> Bool {
            Set(model.sessionSourceRooms[item.sessionId] ?? []).intersection(cachedRooms).isEmpty
        }
        let currentLive = remoteLive + model.sessions.filter(awaitingReport)
        let currentHistory = remoteHistory + model.sessionHistory.filter(awaitingReport)
        model.sessions = DesktopCatalogSources.sessions(
            local: sessions.filter { liveNativeIds.contains($0.sessionId)
                || executionIsOpen($0, in: executions) },
            current: currentLive, remoteSessionIds: remoteIds)
        let liveIds = Set(model.sessions.map(\.sessionId))
        model.sessionHistory = DesktopCatalogSources.sessions(
            local: sessions.filter { !liveNativeIds.contains($0.sessionId)
                && !executionIsOpen($0, in: executions) },
            current: currentHistory, remoteSessionIds: remoteIds).filter { !liveIds.contains($0.sessionId) }
        model.resumeChatQueues(observed: sessions, localOnly: true)
    }

    private static func retainingEnrichment(
        _ fresh: ProjectMeshSnapshot, from previous: ProjectMeshSnapshot?
    ) -> ProjectMeshSnapshot {
        guard let previous, previous.bindings == fresh.bindings,
              previous.publisherEndpointId != nil, previous.cortex != nil else { return fresh }
        var result = fresh
        result.publisherEndpointId = previous.publisherEndpointId
        result.skills = fresh.skills ?? previous.skills
        result.mcpServers = fresh.mcpServers ?? previous.mcpServers
        result.capabilityObservations = fresh.capabilityObservations
            ?? previous.capabilityObservations
        result.modelCatalog = fresh.modelCatalog ?? previous.modelCatalog
        result.backbone = fresh.backbone ?? previous.backbone
        result.repositoryGraphs = fresh.repositoryGraphs ?? previous.repositoryGraphs
        result.cortex = fresh.cortex ?? previous.cortex
        result.knowledge = fresh.knowledge ?? previous.knowledge
        result.supersededKnowledgeRecordIds = fresh.supersededKnowledgeRecordIds
            ?? previous.supersededKnowledgeRecordIds
        return result
    }

    static func apply(_ activity: MacLocalTaskActivity, for session: SessionInfo,
                      to model: AppModel) {
        guard activity.session_id == session.sessionId,
              activity.project_id == session.projectId,
              activity.task_id == session.taskId else { return }
        let entries = activity.entries.map { entry in
            ActivityEntry(id: entry.id, kind: entry.kind, text: entry.text,
                          createdAt: entry.created_at, toolName: entry.tool_name,
                          mcpServer: entry.mcp_server, skill: entry.skill,
                          capabilities: entry.capabilities, durationMs: entry.duration_ms,
                          outcome: entry.outcome,
                          estimatedContextTokens: entry.estimated_context_tokens,
                          attachments: entry.attachments,
                          linesAdded: entry.lines_added, linesRemoved: entry.lines_removed,
                          diffPreview: entry.diff_preview, summary: entry.summary, images: entry.images,
                          callText: entry.call_text, resultText: entry.result_text,
                          detailTruncated: entry.detail_truncated, fileChanges: entry.file_changes,
                          fileChangesComplete: entry.file_changes_complete)
        }
        let incoming = SessionActivity(
            sessionId: session.sessionId, agent: activity.agent ?? session.agent,
            state: activity.state ?? session.state, entries: entries,
            generatedAt: Date().timeIntervalSince1970 * 1_000, history: activity.history
        )
        model.activities[session.sessionId] = model.activities[session.sessionId].map {
            AppModel.mergeActivity(existing: $0, incoming: incoming)
        } ?? incoming
    }

    private static func executionIsOpen(_ session: SessionInfo,
                                        in executions: [ExecutionSessionLink]) -> Bool {
        executions.contains { $0.sessionId == session.sessionId && $0.endedAt == nil }
    }
}
#endif
