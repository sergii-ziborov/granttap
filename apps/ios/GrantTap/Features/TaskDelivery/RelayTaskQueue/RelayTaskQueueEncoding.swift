import Foundation

/// A retry reuses this exact envelope. A fresh nonce with the same job ID is a conflicting operation.
enum RelayTaskQueueEncoding {
    static func prepare(_ message: UserMessage, pairing: Pairing, notBefore: Double,
                        now: Double = floor(Date().timeIntervalSince1970 * 1_000),
                        sendImmediately: Bool = false) throws -> RelayTaskQueueReservation {
        guard validOperation(message), message.requestId == nil,
              let id = message.messageId, id.range(of: "^[A-Za-z0-9][A-Za-z0-9_-]{7,119}$", options: .regularExpression) != nil,
              message.attachmentRefs?.isEmpty != false,
              message.text.utf8.count <= 32_000,
              !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || message.attachments?.isEmpty == false,
              pairing.role == "phone", !pairing.isHub else { throw RelayTaskQueueError.invalidMessage }
        let due = floor(notBefore)
        guard now.isFinite, due.isFinite, due >= now - 300_000,
              due <= now + 29 * 86_400_000 else { throw RelayTaskQueueError.invalidSchedule }
        let expiry = message.type == "user.message.continue" && sendImmediately
            ? now + 30 * 86_400_000 : min(now + 30 * 86_400_000, due + 7 * 86_400_000)
        let token = try Crypto.randomBytes(32).map { String(format: "%02x", $0) }.joined()
        let job = RelayQueuedTask(type: "task.dispatch", jobId: id, token: token,
            sessionId: message.sessionId, notBefore: due, expiresAt: expiry, createdAt: floor(now), operation: message,
            deliveryMode: sendImmediately ? "immediate" : nil)
        let plain = try RelayClient.encodeOmittingNulls(job)
        let box = try Crypto.seal(plain, theirPublicKeyB64: pairing.peerPublicKey, mySecretKeyB64: pairing.mySecretKey)
        let envelope = Envelope(room: pairing.room, from: .phone, to: "machine", senderId: pairing.senderId,
            recipientKeyId: CiphertextRecipient.identifier(publicKey: pairing.peerPublicKey),
            deliveryId: id, wake: nil, expiresAt: expiry, nonce: box.nonce, box: box.box)
        let reservation = RelayTaskQueueReservation(jobId: id, token: token, notBefore: due,
            expiresAt: expiry, createdAt: floor(now), envelope: envelope)
        _ = try reservation.uploadBody()
        return reservation
    }

    private static func validOperation(_ message: UserMessage) -> Bool {
        if message.type == "user.message" { return message.originMessageId == nil }
        guard message.type == "user.message.continue", let origin = message.originMessageId,
              !origin.isEmpty, origin.count <= 180, origin != message.messageId,
              message.sessionId == nil, message.cwd == nil, message.taskOriginId == nil,
              message.retryId == nil, let agent = message.agent,
              ["codex", "claude", "cursor", "grok"].contains(agent) else { return false }
        return true
    }
}
