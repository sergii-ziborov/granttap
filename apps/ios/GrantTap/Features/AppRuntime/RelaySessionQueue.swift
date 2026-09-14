import Foundation
import SwiftUI
import UIKit

extension RelayClient {
    func sendSession<T: Codable>(payload: T, sessionId: String,
                                 ttl: TimeInterval? = 15 * 60,
                                 deliveryId: String? = nil,
                                 completion: ((Error?) -> Void)? = nil) {
        guard let plain = try? Self.encodeOmittingNulls(payload) else {
            completion?(RelaySendError.encoding)
            return
        }

        let room = pairing.room
        guard room == pairing.room,
              !room.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Self.hasExactSessionScope(plain, sessionId: sessionId) else {
            completion?(RelaySendError.invalidSessionScope)
            return
        }

        // Queue coalescible controls even with a cached key. This gives every
        // in-flight generation an identity, so an older failed send cannot be
        // restored after a newer toggle has already won.
        let outcome = enqueuePendingSessionPayload(
            plain: plain,
            room: room,
            sessionId: sessionId,
            ttl: ttl,
            deliveryId: deliveryId,
            completion: completion
        )
        switch outcome {
        case .rejected(let error):
            completion?(error)
        case .queued(let needsSubscription):
            // Close the lookup/enqueue race: an exact grant may have landed
            // between those two operations.
            if sessionKey(for: sessionId) != nil {
                flushPendingSessionPayloads(sessionId: sessionId, room: room)
            } else {
                // The monitor answers with a device-boxed session.key.grant.
                // Further controls coalesce in the same bounded backlog.
                ensureSessionKeySubscription(sessionId: sessionId, room: room,
                                             sendNow: needsSubscription)
            }
        }
    }

    func sessionKey(for sessionId: String) -> String? {
        sessionStateLock.lock()
        let key = sessionKeys[sessionId]
        sessionStateLock.unlock()
        return key
    }

    @discardableResult
    func installForwardedScopeKey(_ key: String, scopeId: String) -> Bool {
        guard !scopeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Crypto.isValidTransferKey(key) else { return false }
        sessionStateLock.lock()
        var updated = sessionKeys
        updated[scopeId] = key
        let saved = SessionKeyVault.save(updated, room: pairing.room)
        if saved { sessionKeys = updated }
        sessionStateLock.unlock()
        return saved
    }

    /// On reconnect, re-request only sessions that still lack keys and flush
    /// exact keyed sessions. The queue itself supplies subscribe coalescing.
    func resumePendingSessionPayloads() {
        let room = pairing.room
        guard !room.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        for sessionId in pendingSessionIds(room: room) {
            if sessionKey(for: sessionId) != nil {
                flushPendingSessionPayloads(sessionId: sessionId, room: room)
            } else {
                ensureSessionKeySubscription(sessionId: sessionId, room: room, sendNow: true)
            }
        }
    }

    /// A grant releases only payloads that were queued by this RelayClient for
    /// the same immutable pairing room and exact session id.
    func flushPendingSessionPayloads(sessionId: String, room: String) {
        guard room == pairing.room,
              !room.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let key = sessionKey(for: sessionId) else { return }
        cancelSessionKeySubscriptionRetry(sessionId: sessionId)

        let now = Date().timeIntervalSince1970
        var ready: [PendingSessionPayload] = []
        sessionStateLock.lock()
        let expired = pruneExpiredPendingSessionPayloadsLocked(now: now)
        let readyKeys = pendingSessionPayloads.keys.filter {
            $0.room == room && $0.sessionId == sessionId
        }
        for queueKey in readyKeys {
            if let entry = pendingSessionPayloads.removeValue(forKey: queueKey) {
                ready.append(entry)
            }
        }
        sessionStateLock.unlock()
        finishExpiredPendingSessionPayloads(expired)

        for entry in ready {
            guard entry.queueKey.room == pairing.room,
                  entry.queueKey.sessionId == sessionId,
                  Self.hasExactSessionScope(entry.plain, sessionId: sessionId) else {
                entry.completion?(RelaySendError.invalidSessionScope)
                continue
            }
            let remainingTTL: TimeInterval?
            if let expiresAt = entry.expiresAt {
                let remaining = expiresAt - now
                guard remaining > 0 else {
                    entry.completion?(RelaySendError.sessionPayloadExpired)
                    continue
                }
                remainingTTL = remaining
            } else {
                remainingTTL = nil
            }
            sendSessionPlain(entry.plain, sessionId: entry.queueKey.sessionId, key: key,
                             ttl: remainingTTL, deliveryId: entry.deliveryId) { [weak self] error in
                guard let self else {
                    entry.completion?(error)
                    return
                }
                self.completeSessionPayloadSend(entry, error: error)
            }
        }
    }

    func enqueuePendingSessionPayload(
        plain: Data,
        room: String,
        sessionId: String,
        ttl: TimeInterval?,
        deliveryId: String?,
        completion: ((Error?) -> Void)?
    ) -> PendingSessionEnqueueOutcome {
        guard plain.count <= Self.maxPendingSessionPayloadSize else {
            return .rejected(RelaySendError.sessionPayloadTooLarge)
        }
        let now = Date().timeIntervalSince1970
        let expiresAt = ttl.map { now + max(0, $0) }
        guard expiresAt.map({ $0 > now }) ?? true else {
            return .rejected(RelaySendError.sessionPayloadExpired)
        }

        let queueKey = PendingSessionQueueKey(
            room: room,
            sessionId: sessionId,
            payload: Self.sessionPayloadCoalescingKey(plain)
                ?? .unique(UUID())
        )
        let entry = PendingSessionPayload(
            id: UUID(),
            queueKey: queueKey,
            plain: plain,
            expiresAt: expiresAt,
            deliveryId: deliveryId ?? UUID().uuidString.lowercased(),
            completion: completion
        )

        sessionStateLock.lock()
        let expired = pruneExpiredPendingSessionPayloadsLocked(now: now)
        let hadPendingSession = pendingSessionPayloads.keys.contains {
            $0.room == room && $0.sessionId == sessionId
        }
        let replaced = pendingSessionPayloads[queueKey]
        let hasCapacity = replaced != nil
            || pendingSessionPayloads.count < Self.maxPendingSessionPayloads
        let outcome: PendingSessionEnqueueOutcome
        if hasCapacity {
            pendingSessionPayloads[queueKey] = entry
            latestSessionPayloadIds[queueKey] = entry.id
            outcome = .queued(needsSubscription: !hadPendingSession)
        } else {
            outcome = .rejected(RelaySendError.sessionQueueFull)
        }
        sessionStateLock.unlock()

        finishExpiredPendingSessionPayloads(expired)
        if let replaced {
            finishSessionPayload(replaced, error: RelaySendError.supersededSessionPayload)
        }
        return outcome
    }
}
