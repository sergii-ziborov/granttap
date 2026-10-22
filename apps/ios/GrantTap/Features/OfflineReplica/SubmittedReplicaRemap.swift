import Foundation

@MainActor
extension AppModel {
    /// A new Task first has a phone UUID. Preserve its submitted attachments
    /// when the provider replaces that stub with its native execution ID.
    func remapSubmittedReplica(from oldId: String, to newId: String) {
        let scope = imageStorageScope(oldId)
        let pictures = ReplicaImageStore.shared
        let documents = ReplicaDocumentStore.shared
        for entry in activities[oldId]?.entries ?? [] {
            let ids = (entry.images ?? []).map(\.id) + (entry.attachments?.contains("Image") == true ? [entry.id] : [])
            for id in ids {
                if let bytes = pictures.load(scope: scope, sessionId: oldId, imageId: id, touch: false) {
                    try? pictures.save(bytes, scope: scope, sessionId: newId, imageId: id)
                }
            }
            let names = Set((entry.attachments ?? []) + documents.names(scope: scope, sessionId: oldId, entryId: entry.id))
            let files = names.compactMap {
                sentAttachment(forEntryId: entry.id, name: $0, sessionId: oldId)
            }.filter { !$0.isImage }
            if !files.isEmpty {
                try? documents.save(files, scope: scope, sessionId: newId, entryId: entry.id)
            }
        }
    }
}
