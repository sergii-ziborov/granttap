import Foundation

extension CapabilityUsageStore {
    static func decodePersisted(_ data: Data) -> [CapabilityUsageEvent] {
        guard let value = try? JSONDecoder().decode(
            [CapabilityUsageEvent].self, from: data
        ) else { return [] }
        let migrated = value.map { item -> CapabilityUsageEvent in
            var item = item
            item.commandPreview = commandPreview(item.commandPreview)
            let exactTarget = chatTarget(
                room: normalizedRoom(item.sourceRoom),
                sessionId: normalizedSession(item.sessionId)
            )
            if let existing = item.deepLinkTarget,
               existing.kind == "chat",
               existing.roomId == exactTarget?.roomId,
               existing.sessionId == exactTarget?.sessionId {
                item.deepLinkTarget = existing
            } else {
                item.deepLinkTarget = exactTarget
            }
            return item
        }
        return Array(migrated.filter { $0.createdAt > clearedAt }
            .sorted { $0.createdAt > $1.createdAt }.prefix(1_000))
    }
}
