import Foundation
import SwiftUI
import UIKit

extension RelayClient {
    func sendSessionPlain(_ plain: Data, sessionId: String, key: String,
                                  ttl: TimeInterval?, deliveryId: String?,
                                  completion: ((Error?) -> Void)?) {
        guard Self.hasExactSessionScope(plain, sessionId: sessionId) else {
            completion?(RelaySendError.invalidSessionScope)
            return
        }
        guard let sealed = Crypto.openableSeal(plain, key: key) else {
            completion?(RelaySendError.encryption)
            return
        }
        let wrapper = SessionSealed(type: "session.sealed", sessionId: sessionId,
                                    nonce: sealed.nonce, box: sealed.box,
                                    createdAt: Date().timeIntervalSince1970 * 1000)
        send(payload: wrapper, ttl: ttl, deliveryId: deliveryId, completion: completion)
    }

    func completeSessionPayloadSend(_ entry: PendingSessionPayload, error: Error?) {
        guard let error else {
            finishSessionPayload(entry, error: nil)
            return
        }
        if let relayError = error as? RelaySendError {
            guard case .disconnected = relayError else {
                // Encoding, encryption, and scope/capacity failures do not
                // become healthy by spinning the socket retry timer.
                finishSessionPayload(entry, error: relayError)
                return
            }
        }
        // Disconnected and URLSession transport errors are transient.
        requeueFailedSessionPayload(entry)
    }

    /// A failed socket handoff keeps the same ciphertext source, absolute
    /// expiry, and relay delivery id. If a newer coalesced value exists, the
    /// older generation is completed as superseded instead of being restored.
    func requeueFailedSessionPayload(_ entry: PendingSessionPayload) {
        let now = Date().timeIntervalSince1970
        guard entry.queueKey.room == pairing.room,
              Self.hasExactSessionScope(entry.plain,
                                        sessionId: entry.queueKey.sessionId) else {
            finishSessionPayload(entry, error: RelaySendError.invalidSessionScope)
            return
        }
        if let expiresAt = entry.expiresAt, expiresAt <= now {
            finishSessionPayload(entry, error: RelaySendError.sessionPayloadExpired)
            return
        }

        var rejection: Error?
        sessionStateLock.lock()
        let expired = pruneExpiredPendingSessionPayloadsLocked(now: now)
        if latestSessionPayloadIds[entry.queueKey] != entry.id {
            rejection = RelaySendError.supersededSessionPayload
        } else if pendingSessionPayloads[entry.queueKey] == nil,
                  pendingSessionPayloads.count < Self.maxPendingSessionPayloads {
            pendingSessionPayloads[entry.queueKey] = entry
        } else if let pending = pendingSessionPayloads[entry.queueKey] {
            if pending.id != entry.id {
                rejection = RelaySendError.supersededSessionPayload
            }
        } else {
            rejection = RelaySendError.sessionQueueFull
        }
        sessionStateLock.unlock()
        finishExpiredPendingSessionPayloads(expired)

        if let rejection {
            finishSessionPayload(entry, error: rejection)
            return
        }
        scheduleSessionQueueRetry(sessionId: entry.queueKey.sessionId,
                                  room: entry.queueKey.room)
    }

    func finishSessionPayload(_ entry: PendingSessionPayload, error: Error?) {
        sessionStateLock.lock()
        if latestSessionPayloadIds[entry.queueKey] == entry.id {
            latestSessionPayloadIds.removeValue(forKey: entry.queueKey)
        }
        sessionStateLock.unlock()
        entry.completion?(error)
    }

    /// One weak timer per exact session retries subscribe (no key) or flush
    /// (key cached). Delay grows 1s → 2s → 4s → 5s and entries' absolute TTLs
    /// provide the terminal bound.
    func ensureSessionKeySubscription(sessionId: String, room: String,
                                              sendNow: Bool) {
        guard room == pairing.room,
              pendingSessionIds(room: room).contains(sessionId),
              sessionKey(for: sessionId) == nil else { return }
        if sendNow { sendSubscription(sessionId: sessionId, active: true) }
        scheduleSessionQueueRetry(sessionId: sessionId, room: room)
    }

    func scheduleSessionQueueRetry(sessionId: String, room: String) {
        guard room == pairing.room else { return }
        sessionStateLock.lock()
        guard sessionSubscriptionRetryTokens[sessionId] == nil,
              pendingSessionPayloads.keys.contains(where: {
                  $0.room == room && $0.sessionId == sessionId
              }) else {
            sessionStateLock.unlock()
            return
        }
        let attempt = sessionSubscriptionRetryAttempts[sessionId, default: 0]
        let token = UUID()
        sessionSubscriptionRetryTokens[sessionId] = token
        sessionSubscriptionRetryAttempts[sessionId] = attempt + 1
        sessionStateLock.unlock()

        let delay = min(5.0, pow(2.0, Double(min(attempt, 3))))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.fireSessionQueueRetry(sessionId: sessionId, room: room, token: token)
        }
    }

    func fireSessionQueueRetry(sessionId: String, room: String, token: UUID) {
        sessionStateLock.lock()
        guard sessionSubscriptionRetryTokens[sessionId] == token else {
            sessionStateLock.unlock()
            return
        }
        sessionSubscriptionRetryTokens.removeValue(forKey: sessionId)
        sessionStateLock.unlock()

        guard pendingSessionIds(room: room).contains(sessionId) else {
            cancelSessionKeySubscriptionRetry(sessionId: sessionId)
            return
        }
        if sessionKey(for: sessionId) != nil {
            flushPendingSessionPayloads(sessionId: sessionId, room: room)
        } else {
            sendSubscription(sessionId: sessionId, active: true)
            scheduleSessionQueueRetry(sessionId: sessionId, room: room)
        }
    }

    func cancelSessionKeySubscriptionRetry(sessionId: String) {
        sessionStateLock.lock()
        sessionSubscriptionRetryTokens.removeValue(forKey: sessionId)
        sessionSubscriptionRetryAttempts.removeValue(forKey: sessionId)
        sessionStateLock.unlock()
    }

    func pendingSessionIds(room: String) -> [String] {
        let now = Date().timeIntervalSince1970
        sessionStateLock.lock()
        let expired = pruneExpiredPendingSessionPayloadsLocked(now: now)
        let ids = Set(pendingSessionPayloads.keys.compactMap { queueKey in
            queueKey.room == room ? queueKey.sessionId : nil
        }).sorted()
        sessionStateLock.unlock()
        finishExpiredPendingSessionPayloads(expired)
        return ids
    }

    /// Must be called with sessionStateLock held. Completion closures are
    /// deliberately invoked by the caller only after unlocking.
    func pruneExpiredPendingSessionPayloadsLocked(now: TimeInterval)
        -> [PendingSessionPayload] {
        var expired: [PendingSessionPayload] = []
        let expiredKeys = pendingSessionPayloads.compactMap { queueKey, entry in
            entry.expiresAt.map({ $0 <= now }) == true ? queueKey : nil
        }
        for queueKey in expiredKeys {
            if let entry = pendingSessionPayloads.removeValue(forKey: queueKey) {
                if latestSessionPayloadIds[queueKey] == entry.id {
                    latestSessionPayloadIds.removeValue(forKey: queueKey)
                }
                expired.append(entry)
            }
        }
        return expired
    }

    func finishExpiredPendingSessionPayloads(_ entries: [PendingSessionPayload]) {
        for entry in entries {
            entry.completion?(RelaySendError.sessionPayloadExpired)
        }
    }

    static func sessionPayloadCoalescingKey(_ plain: Data)
        -> SessionPayloadCoalescingKey? {
        guard let object = try? JSONSerialization.jsonObject(with: plain) as? [String: Any],
              let type = object["type"] as? String else { return nil }
        switch type {
        case "session.access.set":
            return .access
        case "session.mcp.set":
            guard let name = object["serverName"] as? String else { return nil }
            return .mcp(name)
        case "session.skill.set":
            guard let name = object["skillName"] as? String else { return nil }
            return .skill(name)
        case "session.shell.set":
            return .shell
        case "session.compact":
            return .compact
        case "session.control":
            return .control
        case "project.policy.set":
            return .projectPolicy
        default:
            return nil
        }
    }

    /// JSONEncoder turns Swift nil into JSON null; omit those keys instead.
    static func encodeOmittingNulls<T: Encodable>(_ value: T) throws -> Data {
        let raw = try JSONEncoder().encode(value)
        guard let json = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            return raw
        }
        return try JSONSerialization.data(withJSONObject: stripNulls(json), options: [])
    }

    static func stripNulls(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, child) in dict {
                if child is NSNull { continue }
                out[key] = stripNulls(child)
            }
            return out
        }
        if let array = value as? [Any] {
            return array.compactMap { child -> Any? in
                if child is NSNull { return nil }
                return stripNulls(child)
            }
        }
        return value
    }
}
