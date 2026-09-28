#if targetEnvironment(macCatalyst)
import Foundation

struct MacLocalLiveCatalog: Decodable {
    let operation: String
    let computer_id: String
    let generated_at: Double
    let sessions: [SessionInfo]

    func observations(endpointId: String?, nowMs: Double) -> [SessionInfo] {
        guard operation == "desktop.live_catalog", computer_id == endpointId,
              generated_at.isFinite, abs(nowMs - generated_at) <= 60_000,
              sessions.count <= 40 else { return [] }
        return sessions.filter {
            !$0.sessionId.isEmpty && $0.computerId == computer_id
                && $0.projectId?.isEmpty == false && $0.taskId?.isEmpty == false
                && ["working", "waiting", "idle"].contains($0.state)
                && $0.startedAt.isFinite && $0.lastActivityAt.isFinite
                && ($0.title?.utf16.count ?? 0) <= 320
                && ($0.summary?.utf16.count ?? 0) <= 2_000
        }
    }
}

extension MacLocalMCPClient {
    static func liveCatalog(socketPath: String) async throws -> MacLocalLiveCatalog {
        let data = try await read(socketPath: socketPath, operation: "desktop.live_catalog", input: nil)
        return try JSONDecoder().decode(MacLocalLiveCatalog.self, from: data)
    }
}

/// A native observation can replace presentation of a stale close only for
/// the exact current owner. Durable Execution history and ownership stay intact.
enum MacLiveSessionProjection {
    static func session(execution: ExecutionSessionLink, task: ProjectMeshTask?,
                        observed: [SessionInfo], endpointId: String?) -> SessionInfo? {
        guard let task, execution.computerId == endpointId,
              task.taskId == execution.taskId, task.ownerSessionId == execution.sessionId,
              !["completed", "failed", "cancelled", "handoff"].contains(task.state) else { return nil }
        return observed.filter {
            DesktopCatalogSources.matches($0, projectId: task.projectId, execution: execution)
                && (execution.endedAt == nil || $0.lastActivityAt > execution.endedAt!)
        }.max { $0.lastActivityAt < $1.lastActivityAt }
    }
}
#endif
