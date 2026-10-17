import Foundation

/// Which saved queue rows the phone still has to talk to the relay about, in
/// what order, and how soon. A new message is never stuck behind receipt checks.
enum RelayTaskQueueSchedule {
    /// A just-saved or running job settles within seconds on a connected computer.
    static let activeDelaySeconds: Double = 1
    static let waitingDelaySeconds: Double = 5
    static let activeWindowMs: Double = 120_000

    /// Failed and expired jobs cannot change on the relay; the person retries or removes them.
    static func needsSync(_ row: OutgoingDelivery) -> Bool {
        guard row.chatQueue?.relayManaged == true, row.state != .delivered else { return false }
        if row.chatQueue?.cancelRequested == true { return true }
        switch row.relayJob?.serverState {
        case .failed?, .expired?: return false
        default: return true
        }
    }

    /// Uploads first, then receipts, each oldest first.
    static func syncOrder(_ deliveries: [OutgoingDelivery]) -> [String] {
        let rows = TaskDeliveryQueue.oldestFirst(deliveries).filter(needsSync)
        let uploads = rows.filter { $0.relayJob?.serverState == nil && $0.chatQueue?.cancelRequested != true }
        let uploadIds = Set(uploads.map(\.id))
        return uploads.map(\.id) + rows.filter { !uploadIds.contains($0.id) }.map(\.id)
    }

    static func delaySeconds(_ deliveries: [OutgoingDelivery], now: Double) -> Double {
        deliveries.contains { row in
            guard needsSync(row) else { return false }
            if row.chatQueue?.cancelRequested == true || row.relayJob?.serverState == nil
                || row.relayJob?.serverState == .accepted { return true }
            let due = (row.chatQueue?.notBefore ?? row.createdAt) <= now
            let saved = row.chatQueue?.queuedAt ?? row.createdAt
            return due && (row.chatQueue?.sendImmediately == true || now - saved < activeWindowMs)
        } ? activeDelaySeconds : waitingDelaySeconds
    }
}
