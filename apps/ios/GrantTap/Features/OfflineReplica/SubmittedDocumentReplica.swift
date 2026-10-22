import Foundation

@MainActor
extension AppModel {
    func rememberSubmittedDocuments(_ row: OutgoingDelivery) {
        guard let sessionId = row.sessionId else { return }
        let documents = row.attachments.filter { !$0.mimeType.hasPrefix("image/") }.compactMap { file in
            Data(base64Encoded: file.data).map { AttachmentDraft(name: file.name, mimeType: file.mimeType, data: $0) }
        }
        guard !documents.isEmpty else { return }
        try? ReplicaDocumentStore.shared.save(documents, scope: imageStorageScope(sessionId),
                                              sessionId: sessionId, entryId: "local-user-\(row.id)")
    }

    func savedDocument(forEntryId entryId: String, name: String, sessionId: String? = nil) -> AttachmentDraft? {
        guard let id = imageConversation(forEntryId: entryId, preferredSessionId: sessionId) ?? sessionId else { return nil }
        if case .ambiguous = sessionRoomOwnership(forSessionId: id) { return nil }
        let store = ReplicaDocumentStore.shared
        if let file = store.load(scope: imageStorageScope(id), sessionId: id, entryId: entryId, name: name) { return file }
        guard let room = sourceRoom(forSessionId: id) else { return nil }
        return store.load(scope: room, sessionId: id, entryId: entryId, name: name)
    }

    func documentNames(for entry: ActivityEntry, sessionId: String?) -> [String] {
        guard let id = imageConversation(forEntryId: entry.id, preferredSessionId: sessionId) ?? sessionId
        else { return entry.attachments ?? [] }
        if case .ambiguous = sessionRoomOwnership(forSessionId: id) { return entry.attachments ?? [] }
        let store = ReplicaDocumentStore.shared
        let saved = store.names(scope: imageStorageScope(id), sessionId: id, entryId: entry.id)
        let old = sourceRoom(forSessionId: id).map { store.names(scope: $0, sessionId: id, entryId: entry.id) } ?? []
        var names = entry.attachments ?? []
        var seen = Set(names)
        for name in saved + old where seen.insert(name).inserted { names.append(name) }
        return names
    }

    func retainDocumentsForNativeEcho(local: ActivityEntry, caption: ActivityEntry,
                                     incoming: SessionActivity) -> Bool {
        let documents = (local.attachments ?? []).compactMap {
            sentAttachment(forEntryId: local.id, name: $0, sessionId: incoming.sessionId)
        }.filter { !$0.isImage }
        guard !documents.isEmpty else { return true }
        guard caption.kind == "user" else { return false }
        do {
            try ReplicaDocumentStore.shared.save(documents, scope: imageStorageScope(incoming.sessionId),
                sessionId: incoming.sessionId, entryId: caption.id)
            return true
        } catch { return false }
    }
}
