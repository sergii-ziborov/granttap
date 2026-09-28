import Foundation

extension RelayClient {
    func forwardMesh<T: Codable>(
        _ payload: T,
        scopeId: String,
        key: String,
        purpose: String,
        ttl: TimeInterval = 15 * 60,
        completion: ((Error?) -> Void)? = nil
    ) {
        // A chat's transcript and replies travel to a member under the chat's
        // own key, the way its computer sends them to this phone.
        guard ["task", "project", "session"].contains(purpose),
              installForwardedScopeKey(key, scopeId: scopeId) else {
            completion?(RelaySendError.encryption)
            return
        }
        let grant = SessionKeyGrant(
            type: "session.key.grant", sessionId: scopeId, key: key,
            purpose: purpose, createdAt: Date().timeIntervalSince1970 * 1_000
        )
        send(payload: grant, ttl: ttl) { [weak self] error in
            self?.sendForwardedMeshPayload(
                payload, scopeId: scopeId, ttl: ttl, grantError: error,
                completion: completion
            )
        }
    }

    func sendForwardedMeshPayload<T: Codable>(
        _ payload: T, scopeId: String, ttl: TimeInterval,
        grantError: Error?, completion: ((Error?) -> Void)?
    ) {
        guard grantError == nil else { completion?(grantError); return }
        sendSession(payload: payload, sessionId: scopeId, ttl: ttl, completion: completion)
    }
}
