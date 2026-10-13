#if targetEnvironment(macCatalyst)
import Foundation

private struct MacTaskWorkspaceResult: Decodable {
    let operation: String
    let path: String
    let entries: [TaskWorkspaceEntry]?
    let text: String?
    let truncated: Bool
    let nextOffset: Int?
}

extension MacLocalMCPModel {
    func workspacePreview(for session: SessionInfo, query: TaskWorkspaceQuery) async throws
        -> TaskWorkspaceSnapshot {
        guard isReady, let projectId = session.projectId, let taskId = session.taskId,
              session.sessionId == query.sessionId else { throw MacLocalMCPError.unavailable }
        let data = try await MacNativeTransport.invoke(operation: "desktop.task_workspace",
            input: ["project_id": projectId, "task_id": taskId, "session_id": session.sessionId,
                    "mode": query.mode, "path": query.path, "offset": query.offset])
        let result = try JSONDecoder().decode(MacTaskWorkspaceResult.self, from: data)
        let snapshot = TaskWorkspaceSnapshot(type: "session.workspace.result", sessionId: query.sessionId,
            requestId: query.requestId, path: result.path, entries: result.entries, text: result.text,
            truncated: result.truncated, nextOffset: result.nextOffset,
            createdAt: Date().timeIntervalSince1970 * 1_000)
        guard result.operation == "desktop.task_workspace", result.path == query.path,
              snapshot.isWellFormed else { throw MacLocalMCPError.incompatible }
        return snapshot
    }
}
#endif
