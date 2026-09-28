import Foundation

/// Ordered convergence for Task state, mirroring the machine runtime rule for
/// rule so both sides settle on the same Task.
///
/// Snapshots and events reach the phone late, twice, and from several
/// computers. Last-writer-wins let a delayed snapshot restore a previous owner
/// or turn finished work back into working, which is exactly the split brain
/// the Task identity exists to prevent. Every writer raises `revision`, the
/// higher one survives, and ties resolve identically on every device.
enum ProjectMeshConvergence {
    static let terminalStates: Set<String> = ["completed", "failed"]

    static func isTerminal(_ state: String) -> Bool { terminalStates.contains(state) }

    static func revision(_ task: ProjectMeshTask) -> Double { task.revision ?? 0 }

    static func preferred(
        _ current: ProjectMeshTask, _ incoming: ProjectMeshTask
    ) -> ProjectMeshTask {
        if revision(current) != revision(incoming) {
            return revision(incoming) > revision(current) ? incoming : current
        }
        if current.updatedAt != incoming.updatedAt {
            return incoming.updatedAt > current.updatedAt ? incoming : current
        }
        if isTerminal(current.state) != isTerminal(incoming.state) {
            return isTerminal(incoming.state) ? incoming : current
        }
        return orderKey(incoming) > orderKey(current) ? incoming : current
    }

    private static func orderKey(_ task: ProjectMeshTask) -> String {
        [task.state, task.ownerSessionId ?? "", task.title, task.goal]
            .joined(separator: "\u{0}")
    }

    /// An execution closed by a handoff receipt stays closed, even while the
    /// native session it left behind keeps reporting itself as alive.
    static func preferred(
        _ current: ExecutionSessionLink, _ incoming: ExecutionSessionLink
    ) -> ExecutionSessionLink {
        if (current.endedAt != nil) != (incoming.endedAt != nil) {
            var live = current.endedAt == nil ? current : incoming
            live.endedAt = current.endedAt ?? incoming.endedAt
            return live
        }
        let currentAt = current.updatedAt ?? current.startedAt
        let incomingAt = incoming.updatedAt ?? incoming.startedAt
        if currentAt != incomingAt { return incomingAt > currentAt ? incoming : current }
        return incoming.sessionId > current.sessionId ? incoming : current
    }

    /// Whether a handoff receipt may move ownership on this phone.
    ///
    /// The ordinary case is the current owner handing its own Task on. A phone
    /// that was offline can hold an older owner, so the receipt still applies
    /// there — unless this phone already saw that same session hand the Task to
    /// someone else, which makes the receipt a replaced decision arriving late.
    static func movesOwnership(
        _ task: ProjectMeshTask,
        receipt: ProjectHandoffReceipt,
        knownEvents: [ProjectMeshEvent]
    ) -> Bool {
        if task.ownerSessionId == nil || task.ownerSessionId == receipt.sourceSessionId {
            return true
        }
        return !knownEvents.contains { event in
            guard let recorded = event.payload.receipt else { return false }
            return recorded.taskId == receipt.taskId
                && recorded.sourceSessionId == receipt.sourceSessionId
                && recorded.targetSessionId != receipt.targetSessionId
        }
    }

    /// The Task after one event, or `nil` when the event changes nothing.
    static func task(
        after event: ProjectMeshEvent,
        task: ProjectMeshTask,
        knownEvents: [ProjectMeshEvent]
    ) -> ProjectMeshTask? {
        var next = task
        if event.eventType == "HANDOFF_ACCEPTED", let receipt = event.payload.receipt {
            guard movesOwnership(task, receipt: receipt, knownEvents: knownEvents) else { return nil }
            next.ownerSessionId = receipt.targetSessionId
            if !isTerminal(task.state) { next.state = "working" }
            next.updatedAt = max(task.updatedAt, receipt.acceptedAt)
        } else if event.eventType == "TASK_COMPLETED" {
            next.state = "completed"
            next.updatedAt = max(task.updatedAt, event.createdAt)
        } else {
            return nil
        }
        guard next.state != task.state
            || next.ownerSessionId != task.ownerSessionId
            || next.updatedAt != task.updatedAt else { return nil }
        next.revision = revision(task) + 1
        return next
    }
}
