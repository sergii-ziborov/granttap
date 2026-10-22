import Foundation

extension AppModel {
    func recoverSavedChatQueueReceipts(for session: SessionInfo) {
        let id = resolvedSessionId(session.sessionId)
        for row in deliveries where row.sessionId.map(resolvedSessionId) == id
            && row.agent == AgentIdentity.normalize(session.agent) {
            confirmSavedQueueReceipt(row)
        }
    }

    func canSendChatQueuedMessageNow(_ row: OutgoingDelivery) -> Bool {
        guard row.awaitingSessionRemap != true, row.admissionRejected != true else { return false }
        if let generation = row.attemptGeneration, liveDeliveryAttemptGenerations.contains(generation) { return false }
        if row.chatQueue?.relayManaged == true { return ChatMessageQueuePolicy.canCancel(row) }
        return row.chatQueue != nil && row.state != .delivered
    }

    /// Refresh evidence only. Replaying even the same operation after a legacy
    /// computer's dedupe lease expires could start it again.
    func checkLegacyQueuedDelivery(at index: Int) {
        let row = deliveries[index]
        confirmSavedQueueReceipt(row)
        guard deliveries.first(where: { $0.id == row.id })?.state != .delivered else { return }
        guard let sessionId = row.sessionId,
              let room = row.roomId, let relay = relaysByRoom[room] else { return }
        relay.requestSessionEvents(sessionId: resolvedSessionId(sessionId), history: true)
        relay.requestSessionsRefresh()
    }

    func confirmSavedQueueReceipt(_ row: OutgoingDelivery) {
        guard row.chatQueue?.relayManaged != true, row.chatQueue?.waiting == false,
              row.state != .delivered, let id = row.sessionId else { return }
        let resolved = resolvedSessionId(id)
        if row.chatQueue?.transport != .localMCP {
            switch sessionRoomOwnership(forSessionId: id) {
            case .exact(let room): guard row.roomId == room else { return }
            case .ambiguous: return
            case .unknown:
                guard connectionRegistry.connections.count == 1,
                      connectionRegistry.connections.first?.id == row.roomId else { return }
            }
        }
        guard let activity = activities[resolved] ?? activities[id] else { return }
        confirmDeliveriesFromNativeTranscript(activity, sourceRoom: row.roomId)
    }

    func resumeChatQueues(after activity: SessionActivity, fromRoom room: String?) {
        guard ["idle", "finished"].contains(activity.state),
              deliveries.contains(where: {
                  $0.sessionId.map(resolvedSessionId) == resolvedSessionId(activity.sessionId)
                      && $0.chatQueue?.waiting == true && $0.chatQueue?.relayManaged != true
                      && activity.generatedAt >= ($0.chatQueue?.queuedAt ?? $0.createdAt) - 1_000
              }),
              var session = knownSession(for: activity.sessionId, preferredAgent: activity.agent),
              AgentIdentity.normalize(session.agent) == AgentIdentity.normalize(activity.agent) else { return }
        session.state = activity.state
        resumeChatQueues(observed: [session], fromRoom: room)
    }
}
