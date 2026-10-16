import Foundation
import UIKit

@MainActor
extension AppModel {
    /// Submitted bytes become part of the device archive before the outbox sends.
    func rememberSubmittedImages(_ delivery: OutgoingDelivery) -> [MessageImageAttachment] {
        guard let sessionId = delivery.sessionId else { return [] }
        let scope = imageStorageScope(sessionId)
        var pictures: [MessageImageAttachment] = []
        for (index, file) in delivery.attachments.enumerated() {
            guard file.mimeType.hasPrefix("image/"), let bytes = Data(base64Encoded: file.data),
                  MessageImageLoader.thumbnail(bytes) != nil else { continue }
            let id = "local-user-\(delivery.id):attachment:\(index)"
            do {
                try ReplicaImageStore.shared.save(bytes, scope: scope, sessionId: sessionId, imageId: id)
                pictures.append(.init(id: id, name: file.name, markdown: "attachment:\(index)"))
            } catch { continue }
        }
        if !pictures.isEmpty { replicaImagesRevision &+= 1 }
        return pictures
    }

    /// Bind only the same conversation's matched user turn, in native block order.
    /// An incomplete echo keeps the local picture instead of dropping its preview.
    func retainImagesForNativeEcho(local: ActivityEntry, caption: ActivityEntry,
                                   incoming: SessionActivity) -> Bool {
        let pictures = local.images ?? []
        guard !pictures.isEmpty else { return true }
        guard caption.kind == "user" else { return false }
        let groups = Dictionary(grouping: incoming.entries.filter {
            $0.kind == "user" && $0.childThreadId == nil &&
                ($0.attachments?.contains("Image") == true || $0.images?.isEmpty == false)
        }, by: \.createdAt)
        let candidates = groups.filter { abs($0.key - caption.createdAt) <= 2_000 }
            .sorted { abs($0.key - caption.createdAt) < abs($1.key - caption.createdAt) }
        guard let group = candidates.first else { return false }
        if candidates.count > 1,
           abs(group.key - caption.createdAt) == abs(candidates[1].key - caption.createdAt) { return false }
        let nativeIds = group.value.flatMap { entry in
            entry.images?.isEmpty == false ? entry.images!.map(\.id) : [entry.id]
        }
        guard nativeIds.count == pictures.count else { return false }
        let scope = imageStorageScope(incoming.sessionId)
        for (picture, nativeId) in zip(pictures, nativeIds) {
            guard let bytes = cachedMessageImage(sessionId: incoming.sessionId, imageId: picture.id) else {
                return false
            }
            do {
                try ReplicaImageStore.shared.save(bytes, scope: scope,
                    sessionId: incoming.sessionId, imageId: nativeId)
            } catch { return false }
        }
        replicaImagesRevision &+= 1
        return true
    }
}
