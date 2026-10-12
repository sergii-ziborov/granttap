import Foundation

@MainActor
extension AppModel {
    func persistApprovalDecision(_ context: DecisionDeliveryContext, sessionId: String?) -> Bool {
        guard let room = requestSourceRoom[context.requestId] ?? relayForRequest(context.requestId)?.pairing.room
        else { return false }
        guard connectionRegistry.connections.contains(where: { $0.id == room }) else { return false }
        rememberRequestSourceRoom(room, requestId: context.requestId)
        let entry = ApprovalDecisionQueue.Entry(requestId: context.requestId, roomId: room,
            sessionId: Self.normalizedApprovalSession(sessionId), decision: context.decision,
            by: context.by, createdAt: Date().timeIntervalSince1970, note: context.note)
        return approvalDecisionQueue.enqueue(entry)
    }

    func retryConfirmedApproval(_ request: ApprovalRequest, fromRoom room: String) {
        let session = Self.normalizedApprovalSession(request.sessionId)
        guard let entry = approvalDecisionQueue.entry(request.requestId, roomId: room, sessionId: session),
              !wasApprovalTerminal(request.requestId, room: room, sessionId: session) else { return }
        markDecisionInFlight(request.requestId, decision: entry.decision, sessionId: session)
        // Throttle exact pending snapshots, without treating the send as applied.
        if let sentAt = entry.sentAt, Date().timeIntervalSince1970 - sentAt < 10 { return }
        let context = DecisionDeliveryContext(requestId: entry.requestId, decision: entry.decision,
                                             by: entry.by, title: request.title, agent: request.agent, note: entry.note)
        deliverDecision(context, sessionId: session)
    }

    func approvalDecisionDeliveryMessage(_ request: ApprovalRequest) -> String {
        guard let room = requestSourceRoom[request.requestId],
              let entry = approvalDecisionQueue.entry(request.requestId, roomId: room,
                sessionId: Self.normalizedApprovalSession(request.sessionId)), entry.sentAt == nil else {
            return L("Decision sent · waiting for the computer to confirm…")
        }
        return L("Decision saved · waiting for this computer to reconnect…")
    }

    func noteApprovalDecisionSent(_ requestId: String, sessionId: String?, succeeded: Bool) {
        guard let room = requestSourceRoom[requestId],
              let entry = approvalDecisionQueue.entry(requestId, roomId: room,
                sessionId: Self.normalizedApprovalSession(sessionId)) else { return }
        approvalDecisionQueue.markSent(entry, at: succeeded ? Date().timeIntervalSince1970 : nil)
    }

    func removeQueuedApprovalDecision(_ requestId: String) {
        guard let room = requestSourceRoom[requestId] else { return }
        let scope = Self.normalizedApprovalSession(approvalDecisionSessionScope[requestId])
            ?? approvalDecisionQueue.entries.first { $0.requestId == requestId && $0.roomId == room }?.sessionId
        approvalDecisionQueue.remove(requestId, roomId: room, sessionId: scope)
    }
}
