import Foundation

@MainActor
extension AppModel {
    func retryUnstoredApprovalDecisions(inRoom room: String) {
        for entry in approvalDecisionQueue.entries where entry.roomId == room && entry.relayStoredAt == nil {
            retryUnstoredApprovalDecision(entry)
        }
    }

    func retryUnstoredApprovalDecision(_ entry: ApprovalDecisionQueue.Entry) {
        guard let current = approvalDecisionQueue.entry(entry.requestId, roomId: entry.roomId,
                sessionId: entry.sessionId), current.createdAt == entry.createdAt,
              current.decision == entry.decision, current.note == entry.note,
              current.relayStoredAt == nil,
              connectionRegistry.connections.contains(where: { $0.id == entry.roomId }),
              requestSourceRoom[entry.requestId].map({ $0 == entry.roomId }) ?? true else { return }
        guard Date().timeIntervalSince1970 - entry.createdAt < 15 * 60,
              !wasApprovalTerminal(entry.requestId, room: entry.roomId, sessionId: entry.sessionId) else {
            approvalDecisionQueue.remove(entry.requestId, roomId: entry.roomId, sessionId: entry.sessionId)
            clearDecisionInFlight(entry.requestId)
            return
        }
        rememberRequestSourceRoom(entry.roomId, requestId: entry.requestId)
        markDecisionInFlight(entry.requestId, decision: entry.decision, sessionId: entry.sessionId)
        deliverDecision(DecisionDeliveryContext(requestId: entry.requestId, decision: entry.decision,
            by: entry.by, title: entry.requestId, agent: "unknown", note: entry.note), sessionId: entry.sessionId)
    }

    func scheduleApprovalSubmissionRetry(_ requestId: String, after delay: TimeInterval) {
        guard let entry = approvalDecisionQueue.entries.first(where: { $0.requestId == requestId }) else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.retryUnstoredApprovalDecision(entry)
        }
    }
}
