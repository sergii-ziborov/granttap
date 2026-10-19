import Foundation

extension AppModel {
    /// Cancel a failed delivery's local retry lifecycle. A late receipt cannot
    /// recreate a removed operation. This does not interrupt a running agent.
    @discardableResult
    func cancelDelivery(_ id: String) -> Bool {
        guard let row = deliveries.first(where: { $0.id == id }) else { return false }
        if row.chatQueue != nil { return cancelChatQueuedMessage(id) }
        guard row.state == .failed || (row.state == .queued && row.attempts == 0
            && row.relayStoredAt == nil && row.processingAcknowledgedAt == nil) else { return false }
        if let generation = row.attemptGeneration { liveDeliveryAttemptGenerations.remove(generation) }
        deliveries.removeAll { $0.id == id }
        if let origin = localOriginSessionId(for: row) { failDeferredFollowUps(forLocalSessionId: origin) }
        if !demoMode { persistDeliveries() }
        pushToWatch()
        return true
    }

    func deliveryCancellationId(forEntryId entryId: String) -> String? {
        guard entryId.hasPrefix("local-user-") else { return nil }
        let id = String(entryId.dropFirst("local-user-".count))
        guard let row = deliveries.first(where: { $0.id == id }), row.state == .failed else { return nil }
        return row.chatQueue == nil || ChatMessageQueuePolicy.canCancel(row) ? id : nil
    }
}
