import Foundation

/// An attachment already on its way to a computer, ahead of its message.
struct AttachmentUpload: Equatable {
    let attachmentId: String
    let room: String
    var accepted = false
    let sentAt: Double
}

enum AttachmentUploads {
    /// The receipt error a computer answers when a named attachment never came.
    static let missingError = "attachment-missing"

    static func attachmentId() -> String {
        UUID().uuidString.lowercased()
    }
}

extension AppModel {
    /// Send what was just picked, sealed, to the computer the message will go
    /// to, so the message itself has only to name it. A slow link spends its
    /// time on the photo while the person is still typing.
    func preuploadAttachments(_ drafts: [AttachmentDraft], room: String?,
                              now: Double = Date().timeIntervalSince1970 * 1_000) {
        guard let room, let relay = relaysByRoom[room] else { return }
        for draft in drafts where attachmentUploads[draft.id] == nil {
            let upload = AttachmentUpload(attachmentId: AttachmentUploads.attachmentId(), room: room, sentAt: now)
            attachmentUploads[draft.id] = upload
            let payload = UserAttachmentUpload(
                type: "user.attachment", attachmentId: upload.attachmentId, name: draft.name,
                mimeType: draft.mimeType, data: draft.data.base64EncodedString(), createdAt: now
            )
            relay.sendAttachmentUpload(payload) { [weak self] error in
                Task { @MainActor in
                    guard let self, self.attachmentUploads[draft.id]?.attachmentId == upload.attachmentId else { return }
                    if error == nil {
                        self.attachmentUploads[draft.id]?.accepted = true
                    } else {
                        // Not on its way after all: the message carries it itself.
                        self.attachmentUploads.removeValue(forKey: draft.id)
                    }
                }
            }
        }
    }

    /// The ones the relay already took for this room, by id; the rest travel
    /// inside the message.
    func attachmentRefs(for drafts: [AttachmentDraft], room: String?) -> [UserAttachmentRef] {
        guard let room else { return [] }
        let refs = drafts.compactMap { draft -> UserAttachmentRef? in
            guard let upload = attachmentUploads[draft.id], upload.accepted, upload.room == room else { return nil }
            return UserAttachmentRef(attachmentId: upload.attachmentId, name: draft.name, mimeType: draft.mimeType)
        }
        // A message names all of its attachments or none: half by id and half
        // inline would order them by chance.
        return refs.count == drafts.count ? refs : []
    }

    func forgetAttachmentUploads(for drafts: [AttachmentDraft]) {
        for draft in drafts { attachmentUploads.removeValue(forKey: draft.id) }
    }
}
