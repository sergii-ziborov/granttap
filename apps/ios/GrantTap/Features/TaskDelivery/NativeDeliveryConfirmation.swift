import Foundation

extension AppModel {
    /// A native user entry confirms message admission even when a desktop-owned
    /// turn has no headless completion event. Each echo belongs to one operation.
    func confirmDeliveriesFromNativeTranscript(_ activity: SessionActivity, sourceRoom: String?) {
        let sessionId = resolvedSessionId(activity.sessionId)
        let scoped = deliveries.filter {
            $0.sessionId.map(resolvedSessionId) == sessionId && $0.roomId == sourceRoom
                && ($0.agent == nil || $0.agent == AgentIdentity.normalize(activity.agent))
        }
        var used = Set(scoped.compactMap(\.nativeEchoId))
        let candidates = TaskDeliveryQueue.oldestFirst(scoped.filter {
            $0.state != .delivered && $0.requestId == nil
                && $0.chatQueue?.waiting != true && $0.chatQueue?.relayManaged != true
                && ($0.attempts > 0 || $0.processingAcknowledgedAt != nil || $0.relayStoredAt != nil)
        })
        var changed = false
        for row in candidates {
            let text = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let dispatchedAt = row.manualRetryStartedAt ?? row.transportAttemptStartedAt ?? row.createdAt
            guard !text.isEmpty,
                  let echo = activity.entries.filter({ entry in
                      entry.kind == "user" && !entry.id.hasPrefix("local-user-")
                          && !used.contains(entry.id) && entry.createdAt >= dispatchedAt - 1_000
                          && entry.text.trimmingCharacters(in: .whitespacesAndNewlines) == text
                          && Self.echoMatches(row, remoteAt: entry.createdAt)
                  }).min(by: {
                      Self.echoSkew(row, remoteAt: $0.createdAt) < Self.echoSkew(row, remoteAt: $1.createdAt)
                  }), let index = deliveries.firstIndex(where: { $0.id == row.id }) else { continue }
            used.insert(echo.id)
            if let generation = row.attemptGeneration { liveDeliveryAttemptGenerations.remove(generation) }
            deliveries[index].nativeEchoId = echo.id
            deliveries[index].state = .delivered
            deliveries[index].updatedAt = Date().timeIntervalSince1970 * 1_000
            deliveries[index].error = nil
            deliveries[index].nextRetryAt = nil
            deliveries[index].attemptGeneration = nil
            deliveries[index].processingAcknowledgedAt = nil
            deliveries[index].processingRetryStartedAt = nil
            changed = true
        }
        if changed { persistDeliveries() }
    }
}
