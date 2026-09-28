import Foundation

/// What a computer is doing for a Project right now, by Task.
///
/// A computer row said how many repositories it holds and whether it answers;
/// it did not say what it is busy with, which is the first thing a person
/// wants from a list of computers. An execution is "now" while its chat is
/// working on this phone, or while the computer last saw it alive a moment
/// ago; a chat that went quiet an hour ago is not work in progress.
enum ProjectComputerWork {
    static let recentMs: Double = 15 * 60 * 1_000

    struct Item: Equatable, Identifiable {
        let taskId: String
        let title: String
        let provider: String
        let working: Bool
        var id: String { taskId }
    }

    static func current(
        snapshot: ProjectMeshSnapshot, endpointId: String, sessions: [SessionInfo],
        now: Double = Date().timeIntervalSince1970 * 1_000
    ) -> [Item] {
        let sessionsById = Dictionary(sessions.map { ($0.sessionId, $0) }, uniquingKeysWith: { first, _ in first })
        var items: [Item] = []
        var seen = Set<String>()
        let open = snapshot.executions
            .filter { $0.computerId == endpointId && $0.endedAt == nil }
            .sorted { $0.lastSeenAt > $1.lastSeenAt }
        for execution in open {
            guard let task = snapshot.tasks.first(where: { $0.taskId == execution.taskId }),
                  !["completed", "failed"].contains(task.state) else { continue }
            let session = sessionsById[execution.sessionId]
            let working = session?.state == "working" && session?.isPaused != true
            let recent = now - execution.lastSeenAt <= recentMs
            guard working || recent else { continue }
            guard seen.insert(task.taskId).inserted else { continue }
            items.append(Item(
                taskId: task.taskId, title: ProjectMeshTaskTitle.text(task, session: session),
                provider: execution.provider, working: working
            ))
        }
        return items
    }

    /// "Working on: Fix pairing · Codex", or what else is true.
    static func line(_ items: [Item]) -> String? {
        guard let first = items.first else { return nil }
        let head = "\(first.title) · \(AgentIdentity.shortName(first.provider))"
        let rest = items.count > 1 ? " +\(items.count - 1)" : ""
        return String(format: L(first.working ? "Working on: %@" : "Last on: %@"), head + rest)
    }
}
