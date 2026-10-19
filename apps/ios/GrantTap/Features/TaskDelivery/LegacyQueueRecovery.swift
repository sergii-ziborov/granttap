import Foundation

extension AppModel {
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
        guard let sessionId = row.sessionId,
              let room = row.roomId, let relay = relaysByRoom[room] else { return }
        relay.requestSessionEvents(sessionId: resolvedSessionId(sessionId), history: true)
        relay.requestSessionsRefresh()
    }
}
