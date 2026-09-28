import Foundation

/// Desktop combines same-user MCP observations and authenticated computer reports.
/// Refreshing either source must not replace the other computer's catalog.
enum DesktopCatalogSources {
    static func sessions(local: [SessionInfo], current: [SessionInfo],
                         remoteSessionIds: Set<String>) -> [SessionInfo] {
        let remote = current.filter { remoteSessionIds.contains($0.sessionId) }.map { report in
            guard let computer = report.computerId, !computer.isEmpty,
                  let observed = local.filter({
                      $0.sessionId == report.sessionId && $0.agent == report.agent
                          && $0.computerId == computer
                  }).max(by: { $0.lastActivityAt < $1.lastActivityAt }),
                  observed.lastActivityAt >= report.lastActivityAt else { return report }
            return observed
        }
        let remoteIds = Set(remote.map(\.sessionId))
        return remote + local.filter { !remoteIds.contains($0.sessionId) }
    }

    static func matches(_ session: SessionInfo, projectId: String,
                        execution: ExecutionSessionLink) -> Bool {
        session.projectId == projectId && session.taskId == execution.taskId
            && session.sessionId == execution.sessionId && session.agent == execution.provider
            && session.computerId == execution.computerId
    }

    static func snapshots(local: [String: ProjectMeshSnapshot],
                          current: [String: ProjectMeshSnapshot],
                          previousLocalIds: Set<String>, remoteProjectIds: Set<String>,
                          nowMs: Double) -> [String: ProjectMeshSnapshot] {
        var result = current.filter { !previousLocalIds.contains($0.key) || remoteProjectIds.contains($0.key) }
        for (id, fresh) in local {
            result[id] = remoteProjectIds.contains(id)
                ? ProjectMeshLogic.merged(current: current[id], incoming: fresh, nowMs: nowMs) : fresh
        }
        return result
    }
}
