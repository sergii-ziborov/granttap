import Foundation

extension AppModel {
    /// Only an explicit user retry can renew a computer-refused operation.
    /// Rename its existing local bubble so the timeline still has one message.
    func renewRejectedDeliveryIdentity(at index: Int) {
        guard deliveries[index].rejectedByComputer == true else { return }
        let oldId = deliveries[index].id
        let newId = UUID().uuidString
        deliveries[index].id = newId
        deliveries[index].rejectedByComputer = nil
        guard let sessionId = deliveries[index].sessionId else { return }
        let aliases = Set([sessionId, resolvedSessionId(sessionId)])
        let prefix = "local-user-\(oldId)"
        var changed: [String: SessionActivity] = [:]
        for alias in aliases {
            guard let activity = activities[alias] else { continue }
            var entries = activity.entries
            var found = false
            for entryIndex in entries.indices {
                let entryId = entries[entryIndex].id
                guard entryId == prefix || entryId.hasPrefix(prefix + "-") else { continue }
                entries[entryIndex].id = "local-user-\(newId)" + entryId.dropFirst(prefix.count)
                found = true
            }
            if found {
                changed[alias] = SessionActivity(type: activity.type, sessionId: activity.sessionId,
                    agent: activity.agent, state: activity.state, threadId: activity.threadId,
                    entries: entries, generatedAt: activity.generatedAt, history: activity.history)
            }
        }
        guard !changed.isEmpty else { return }
        activities.merge(changed) { _, new in new }
        if !demoMode { SessionActivityPersistence.save(changed) }
    }
}
