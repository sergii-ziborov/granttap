import Foundation

/// What of a member's snapshot this phone takes.
///
/// A member's phone forwards the mesh as it sees it: its own computers'
/// Tasks and executions, and whatever it was handed of everyone else's. The
/// latter is a copy of what this phone already knows, and a copy is not an
/// authority: a member who could raise a Task's revision would hand it a new
/// owner, or close it, from the outside. So a snapshot from a member
/// contributes only what the member's side may speak for — never what this
/// phone's own computers reported, never in the name of their chats, and
/// never the Project itself.
enum MemberContribution {
    struct Owned {
        /// Chats on this phone's own computers, by session id.
        let isOwnChat: (String) -> Bool
        /// Names this phone's own computers publish under.
        let ownComputers: Set<String>
        /// The member room that first spoke for a row, by row identity.
        var contributor: (String) -> String? = { _ in nil }
    }

    static func taskKey(_ taskId: String) -> String { "task\u{1f}\(taskId)" }
    static func executionKey(_ executionId: String) -> String { "exec\u{1f}\(executionId)" }
    static func claimKey(_ claimId: String) -> String { "claim\u{1f}\(claimId)" }
    static func chatKey(_ sessionId: String) -> String { "chat\u{1f}\(sessionId)" }

    /// The rows a contribution speaks for, so the room that sent it is
    /// remembered and no other room can speak for them afterwards.
    static func rowKeys(of snapshot: ProjectMeshSnapshot) -> [String] {
        snapshot.tasks.map { taskKey($0.taskId) }
            + snapshot.executions.map { executionKey($0.id) }
            + snapshot.executions.map { chatKey($0.sessionId) }
            + snapshot.claims.map { claimKey($0.claimId) }
    }

    static func filtered(
        _ snapshot: ProjectMeshSnapshot, known: ProjectMeshSnapshot?, rules: MemberRules, owned: Owned,
        speakingFor room: String = ""
    ) -> ProjectMeshSnapshot {
        // A row another room already spoke for is that room's; a row nobody
        // has spoken for yet is the sender's.
        func mine(_ key: String) -> Bool {
            guard let first = owned.contributor(key) else { return true }
            return first == room
        }
        let knownTasks = Dictionary((known?.tasks ?? []).map { ($0.taskId, $0) }, uniquingKeysWith: { first, _ in first })
        // A Task this phone's own computers own, or that the member would hand
        // to one of their chats, is not the member's to change.
        let tasks = snapshot.tasks.filter { task in
            if let owner = knownTasks[task.taskId]?.ownerSessionId, owned.isOwnChat(owner) { return false }
            if let owner = task.ownerSessionId, owned.isOwnChat(owner) { return false }
            if let owner = task.ownerSessionId, !mine(chatKey(owner)) { return false }
            return mine(taskKey(task.taskId))
        }
        let contributed = Set(tasks.map(\.taskId))
        var filtered = snapshot
        if let known { filtered = withProject(filtered, known.project) }
        filtered.tasks = tasks
        filtered.executions = snapshot.executions.filter {
            !owned.ownComputers.contains($0.computerId) && !owned.isOwnChat($0.sessionId)
                && mine(executionKey($0.id)) && mine(chatKey($0.sessionId))
        }
        // A claim's owner is not the sender's to change: a claim this phone
        // already holds keeps the owner it was made under, whoever republishes it.
        let knownClaims = Dictionary(
            (known?.claims ?? []).map { ($0.claimId, $0) }, uniquingKeysWith: { first, _ in first }
        )
        filtered.claims = snapshot.claims.filter { claim in
            if owned.isOwnChat(claim.ownerSessionId) { return false }
            if let held = knownClaims[claim.claimId], held.ownerSessionId != claim.ownerSessionId { return false }
            return mine(claimKey(claim.claimId)) && mine(chatKey(claim.ownerSessionId))
        }
        filtered.dependencies = snapshot.dependencies.filter { contributed.contains($0.taskId) }
        filtered.events = snapshot.events.filter {
            !owned.isOwnChat($0.sourceSessionId) && mine(chatKey($0.sourceSessionId))
                && MemberHubPolicy.allowsEvent($0.eventType, rules: rules)
        }
        filtered.bindings = snapshot.bindings.map { bindings in
            bindings.filter { !owned.ownComputers.contains($0.endpointId) }
        }
        return filtered
    }

    /// The Project as this phone knows it; a member's copy does not rename it.
    private static func withProject(_ snapshot: ProjectMeshSnapshot, _ project: ProjectMeshProject) -> ProjectMeshSnapshot {
        ProjectMeshSnapshot(
            type: snapshot.type, sessionId: snapshot.sessionId, projectId: snapshot.projectId, project: project,
            bindings: snapshot.bindings, peers: snapshot.peers, skills: snapshot.skills,
            incomplete: snapshot.incomplete, tasks: snapshot.tasks, executions: snapshot.executions,
            claims: snapshot.claims, dependencies: snapshot.dependencies, events: snapshot.events,
            generatedAt: snapshot.generatedAt
        )
    }
}
