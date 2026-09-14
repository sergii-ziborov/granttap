import Foundation

/// One row of the pre-flight the user sees before a task is moved.
struct HandoffReadinessCheck: Identifiable, Equatable {
    let id: String
    let title: String
    let ready: Bool
    let detail: String
    /// Ready, but worth a look: the row does not block the move.
    var warning: Bool = false
}

/// Whether this Task may leave this computer at all.
///
/// A Task Capsule carries committed facts, so uncommitted work would stay
/// behind while the Task visibly continued elsewhere. That is refused here and
/// again on the source computer rather than silently narrowing the handoff.
enum TaskHandoffReadiness {
    static let uncommittedReason =
        "This task has uncommitted changes. Commit or checkpoint them before moving the task."

    /// An unread working tree blocks the move. Only a positive reading of a
    /// clean checkout releases it, because "we could not look" is not "clean".
    static let unreadableWorkingTreeReason =
        "GrantTap could not read this working tree, so it cannot promise a commit carries everything."

    static func checks(
        session: SessionInfo,
        snapshot: ProjectMeshSnapshot?,
        destinationSelected: Bool,
        targetProviderEnabled: Bool,
        checkpoint: Bool = false
    ) -> [HandoffReadinessCheck] {
        let execution = snapshot?.executions.first {
            $0.sessionId == session.sessionId && $0.endedAt == nil
        }
        let conflict = conflictingClaim(session: session, snapshot: snapshot)
        let neighbour = moduleOverlapClaim(session: session, snapshot: snapshot)
        return [
            HandoffReadinessCheck(
                id: "destination", title: L("Destination"), ready: destinationSelected,
                detail: destinationSelected
                    ? L("Selected")
                    : L("Link a second computer to move this task.")
            ),
            // Uncommitted work is the usual reason a Task cannot leave. With a
            // checkpoint the source computer commits it to a branch of its own
            // first — local, never pushed — so the move no longer waits on a
            // commit made by hand.
            HandoffReadinessCheck(
                id: "workingTree", title: L("Working tree"),
                ready: execution?.uncommitted == false || (checkpoint && execution?.uncommitted == true),
                detail: checkpoint && execution?.uncommitted == true
                    ? L("Uncommitted work will be committed to a checkpoint branch before the move.")
                    : workingTreeDetail(execution),
                warning: checkpoint && execution?.uncommitted == true
            ),
            HandoffReadinessCheck(
                id: "claims", title: L("Claims"), ready: conflict == nil,
                detail: conflict.map { "\($0.ownerSessionId) · \($0.resource)" }
                    ?? L("No overlapping resource claims")
            ),
            // The merge conflict that has not happened yet: someone else is in
            // the same module. Said, not enforced — two agents can share one.
            HandoffReadinessCheck(
                id: "module", title: L("Same module"), ready: true,
                detail: neighbour.map { "\($0.ownerSessionId) · \($0.resource)" }
                    ?? L("No one else is working in these modules"),
                warning: neighbour != nil
            ),
            HandoffReadinessCheck(
                id: "targetAgent", title: L("Target agent"), ready: targetProviderEnabled,
                detail: targetProviderEnabled
                    ? L("Ready")
                    : L("Enable this agent in Agents & Mesh first.")
            ),
            HandoffReadinessCheck(
                id: "commit", title: L("Commit"), ready: true,
                detail: L("Checked on the destination computer when it accepts.")
            ),
        ]
    }

    static func isReady(_ checks: [HandoffReadinessCheck]) -> Bool {
        checks.allSatisfy(\.ready)
    }

    static func blockedReason(_ checks: [HandoffReadinessCheck]) -> String? {
        checks.first { !$0.ready }?.detail
    }

    private static func workingTreeDetail(_ execution: ExecutionSessionLink?) -> String {
        switch execution?.uncommitted {
        case false: return L("Clean")
        case true: return L(uncommittedReason)
        default: return L(unreadableWorkingTreeReason)
        }
    }

    /// Directory segments that mark the start of a module. The module is the
    /// child of the deepest container that is still a directory
    /// (`crates/X/src/a.rs` → `crates/X`). Mirrors the bridge, vector for
    /// vector, so the phone and every computer reach the same answer.
    private static let moduleContainers: Set<String> = [
        "apps", "packages", "crates", "services", "modules", "libs", "features",
        "src", "lib", "internal", "cmd", "pkg", "sources", "tests",
    ]

    static func moduleRoot(_ path: String) -> String {
        let parts = path.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0 != "." }
        guard parts.count > 1 else { return "" }
        let last = parts.count - 1
        var index = last - 1
        while index >= 0 {
            if moduleContainers.contains(parts[index].lowercased()), index + 1 < last {
                return parts[0...(index + 1)].joined(separator: "/")
            }
            index -= 1
        }
        return parts[0..<last].joined(separator: "/")
    }

    enum OverlapKind { case file, module }

    static func overlapKind(_ left: String, _ right: String) -> OverlapKind? {
        if resourcesOverlap(left, right) { return .file }
        let a = moduleRoot(left), b = moduleRoot(right)
        return !a.isEmpty && a == b ? .module : nil
    }

    /// Someone else's claim in the same module as this Task's own — the merge
    /// conflict that has not happened yet. A warning, never a block.
    static func moduleOverlapClaim(
        session: SessionInfo, snapshot: ProjectMeshSnapshot?
    ) -> ProjectResourceClaim? {
        guard let snapshot, let taskId = session.taskId else { return nil }
        let owned = snapshot.claims.filter { $0.taskId == taskId }.map(\.resource)
        return snapshot.claims.first { claim in
            claim.taskId != taskId
                && claim.ownerSessionId != session.sessionId
                && owned.contains { overlapKind($0, claim.resource) == .module }
        }
    }

    static func resourcesOverlap(_ left: String, _ right: String) -> Bool {
        if left == right || glob(left, matches: right) || glob(right, matches: left) {
            return true
        }
        let prefix: (String) -> String = { value in
            String(value.prefix { $0 != "*" }).replacingOccurrences(
                of: "/$", with: "", options: .regularExpression
            )
        }
        let first = prefix(left)
        let second = prefix(right)
        return !first.isEmpty && !second.isEmpty
            && (first.hasPrefix(second) || second.hasPrefix(first))
    }

    private static func glob(_ pattern: String, matches candidate: String) -> Bool {
        var expression = "^"
        var index = pattern.startIndex
        let special = CharacterSet(charactersIn: ".+^${}()|[]\\")
        while index < pattern.endIndex {
            let character = pattern[index]
            if character == "*" {
                let next = pattern.index(after: index)
                if next < pattern.endIndex, pattern[next] == "*" {
                    expression += ".*"
                    index = pattern.index(after: next)
                    continue
                }
                expression += "[^/]*"
            } else {
                if String(character).rangeOfCharacter(from: special) != nil { expression += "\\" }
                expression.append(character)
            }
            index = pattern.index(after: index)
        }
        return candidate.range(of: expression + "$", options: .regularExpression) != nil
    }

    private static func conflictingClaim(
        session: SessionInfo,
        snapshot: ProjectMeshSnapshot?
    ) -> ProjectResourceClaim? {
        guard let snapshot, let taskId = session.taskId else { return nil }
        let owned = snapshot.claims.filter { $0.taskId == taskId }.map(\.resource)
        return snapshot.claims.first { claim in
            claim.taskId != taskId
                && claim.ownerSessionId != session.sessionId
                && owned.contains { resourcesOverlap($0, claim.resource) }
        }
    }
}
