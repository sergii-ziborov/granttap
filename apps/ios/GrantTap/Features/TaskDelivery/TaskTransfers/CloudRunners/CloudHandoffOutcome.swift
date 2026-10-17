import Foundation

/// What became of a request to start a Task in a cloud runner: the external
/// execution the computer recorded, or its refusal, read from the same Project
/// snapshot as every other transfer.
enum CloudHandoffOutcome: Equatable {
    case waiting
    case started(ExecutionSessionLink)
    case failed(String)

    static func observe(session: SessionInfo, snapshot: ProjectMeshSnapshot?, target: TaskHandoffCloudTarget,
                        computer: String, previousEvents: Set<String>, notBefore: Double) -> Self {
        guard let snapshot, snapshot.projectId == session.projectId else { return .waiting }
        if let run = snapshot.executions.last(where: {
            $0.taskId == session.taskId && $0.external?.provider == target.provider
                && $0.provider == target.provider && $0.computerId == computer && $0.startedAt >= notBefore
        }) {
            return .started(run)
        }
        switch TaskHandoffOutcome.observe(session: session, snapshot: snapshot, provider: target.provider,
                                          computer: computer, previousEvents: previousEvents, notBefore: notBefore) {
        case .failed(let reason): return .failed(reason)
        case .waiting, .prepared: return .waiting
        }
    }

    /// The same bounded, read-only wait a computer transfer uses.
    @MainActor
    static func wait(lookup: () -> Self, observing: () -> Bool, attempts: Int = 240,
                     pause: () async throws -> Void = { try await Task.sleep(nanoseconds: 500_000_000) }) async -> Self? {
        for _ in 0..<attempts {
            guard observing() else { return nil }
            let outcome = lookup()
            if outcome != .waiting { return outcome }
            do { try await pause() } catch { return nil }
        }
        return .waiting
    }
}
