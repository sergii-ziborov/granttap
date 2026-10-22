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
        var usedPictureTimes = Set(activity.entries.filter { used.contains($0.id) }.map(\.createdAt))
        let candidates = TaskDeliveryQueue.oldestFirst(scoped.filter {
            $0.state != .delivered && $0.requestId == nil
                && $0.rejectedByComputer != true && $0.admissionRejected != true
                && $0.chatQueue?.waiting != true && $0.chatQueue?.relayManaged != true
                && ($0.attempts > 0 || $0.processingAcknowledgedAt != nil || $0.relayStoredAt != nil)
        })
        var changed = false
        for row in candidates {
            let text = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let dispatchedAt = row.manualRetryStartedAt ?? row.transportAttemptStartedAt ?? row.createdAt
            let pictureOnly = text.isEmpty && !row.attachments.isEmpty
                && row.attachments.allSatisfy { $0.mimeType.hasPrefix("image/") }
            guard !text.isEmpty || !row.attachments.isEmpty,
                  let echo = activity.entries.filter({ entry in
                      entry.kind == "user" && entry.childThreadId == nil && !entry.id.hasPrefix("local-user-")
                          && !used.contains(entry.id) && entry.createdAt >= dispatchedAt - 1_000
                          && Self.nativeEchoTextMatches(row, text: entry.text)
                          && (!pictureOnly || (!usedPictureTimes.contains(entry.createdAt)
                              && Self.pictureCount(at: entry.createdAt, in: activity.entries) == row.attachments.count))
                          && Self.echoMatches(row, remoteAt: entry.createdAt)
                  }).min(by: {
                      Self.echoSkew(row, remoteAt: $0.createdAt) < Self.echoSkew(row, remoteAt: $1.createdAt)
                  }), let index = deliveries.firstIndex(where: { $0.id == row.id }) else { continue }
            used.insert(echo.id)
            if pictureOnly { usedPictureTimes.insert(echo.createdAt) }
            let local = ActivityEntry(id: "local-user-\(row.id)", kind: "user", text: row.text,
                createdAt: row.createdAt, attachments: row.attachments.map(\.name), images: rememberSubmittedImages(row))
            _ = retainImagesForNativeEcho(local: local, caption: echo, incoming: activity)
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

    static func nativeEchoTextMatches(_ row: OutgoingDelivery, text: String) -> Bool {
        let expected = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let actual = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if expected.isEmpty, !row.attachments.isEmpty {
            return actual == "Please inspect the attached content."
                || (actual.isEmpty && row.attachments.allSatisfy { $0.mimeType.hasPrefix("image/") })
        }
        return actual == expected
    }

    private static func pictureCount(at timestamp: Double, in entries: [ActivityEntry]) -> Int {
        entries.filter { $0.kind == "user" && $0.childThreadId == nil && $0.createdAt == timestamp }
            .reduce(0) { $0 + ($1.images?.count ?? ($1.attachments?.filter { $0 == "Image" }.count ?? 0)) }
    }
}
