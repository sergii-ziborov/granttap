import Foundation

/// One chat runs on one computer.
///
/// A Mac renamed by the network it joins ("Mac.lan" at home,
/// "Serhiis-MacBook-Pro.local" on the road) left the same chat recorded as
/// two executions, one per name, and a Task screen or a report listed one
/// conversation twice, on two computers. The computer retires the rows under
/// its former names, but keeps them so every phone learns the same, so they
/// are folded here: rows of one chat are one execution, under the name that
/// is live, from the earliest start, over only when every row is over.
enum ExecutionCoalescing {
    static func coalesced(_ executions: [ExecutionSessionLink]) -> [ExecutionSessionLink] {
        var order: [String] = []
        var groups: [String: [ExecutionSessionLink]] = [:]
        for execution in executions {
            let key = "\(execution.provider)\u{1f}\(execution.sessionId)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(execution)
        }
        return order.compactMap { key in groups[key].map(merge) }
    }

    static func merge(_ rows: [ExecutionSessionLink]) -> ExecutionSessionLink {
        guard rows.count > 1, let first = rows.first else { return rows[0] }
        let live = rows.filter { $0.endedAt == nil }
        let primary = live.max { $0.lastSeenAt < $1.lastSeenAt }
            ?? rows.max { $0.lastSeenAt < $1.lastSeenAt } ?? first
        let allEnded = rows.allSatisfy { $0.endedAt != nil }
        return ExecutionSessionLink(
            taskId: primary.taskId, sessionId: primary.sessionId, provider: primary.provider,
            actorId: primary.actorId, computerId: primary.computerId, workspace: primary.workspace,
            repositoryId: primary.repositoryId ?? rows.compactMap(\.repositoryId).first,
            branch: primary.branch ?? rows.compactMap(\.branch).first,
            worktree: primary.worktree ?? rows.compactMap(\.worktree).first,
            uncommitted: primary.uncommitted,
            updatedAt: rows.compactMap(\.updatedAt).max(),
            activeAt: primary.activeAt ?? rows.compactMap(\.activeAt).max(),
            startedAt: rows.map(\.startedAt).min() ?? primary.startedAt,
            endedAt: allEnded ? rows.compactMap(\.endedAt).max() : nil
        )
    }
}
