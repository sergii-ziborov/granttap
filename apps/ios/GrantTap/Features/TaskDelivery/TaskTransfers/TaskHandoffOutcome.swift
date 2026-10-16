import Foundation

enum TaskHandoffOutcome: Equatable {
    case waiting
    case prepared(String)
    case failed(String)

    static func observe(session: SessionInfo, snapshot: ProjectMeshSnapshot?,
                        provider: String, computer: String, previousEvents: Set<String>,
                        notBefore: Double = 0) -> Self {
        guard let snapshot, snapshot.projectId == session.projectId else { return .waiting }
        let events = snapshot.events.filter {
            !previousEvents.contains($0.eventId) && $0.createdAt >= notBefore && $0.taskId == session.taskId
                && $0.projectId == session.projectId
        }
        let request = events.last {
            $0.eventType == "HANDOFF_REQUEST" && $0.sourceSessionId == session.sessionId
                && $0.payload.capsule?.targetProvider == provider
                && $0.payload.capsule?.targetComputer == computer
        }
        if let request, let capsule = request.payload.capsule,
           let hash = ProjectMeshReceiptValidator.capsuleHash(capsule),
           let accepted = events.last(where: { event in
               guard let receipt = event.payload.receipt else { return false }
               return receipt.sourceSessionId == session.sessionId && receipt.capsuleHash == hash
                   && ProjectMeshReceiptValidator.valid(receipt, for: event, in: snapshot)
           }), let receipt = accepted.payload.receipt {
            return .prepared(receipt.targetSessionId)
        }
        if let failure = events.last(where: {
            ($0.eventType == "TASK_BLOCKED" && $0.sourceSessionId == session.sessionId)
                || ($0.eventType == "HANDOFF_REJECTED" && request != nil
                    && $0.targetSessionId == session.sessionId
                    && $0.sourceSessionId == "computer:\(computer)")
        }) {
            return .failed(failure.payload.reason ?? L("The handoff was not accepted."))
        }
        return .waiting
    }
}
