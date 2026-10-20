import Foundation

struct SubscriptionRetentionOffer: Equatable {
    let productID: String
    let offerID: String
    let keyID: String
    let nonce: UUID
    let signature: Data
    let timestamp: Int
    let expiresAt: Date

    init(_ value: [String: Any], now: Date = Date()) throws {
        guard let product = value["productId"] as? String,
              let plan = SubscriptionProduct(rawValue: product),
              let offer = value["offerId"] as? String,
              offer == Self.identifier(for: plan),
              let key = value["keyId"] as? String, !key.isEmpty,
              let nonceText = value["nonce"] as? String, let nonce = UUID(uuidString: nonceText),
              let encoded = value["signature"] as? String, let signature = Data(base64Encoded: encoded),
              !signature.isEmpty, signature.count <= 256,
              let timestamp = value["timestamp"] as? Int,
              let expiry = value["expiresAt"] as? Double, expiry.isFinite,
              timestamp > 0, Double(timestamp) <= now.timeIntervalSince1970 * 1_000 + 60_000,
              expiry > now.timeIntervalSince1970 * 1_000,
              expiry <= Double(timestamp) + 24 * 60 * 60 * 1_000 else {
            throw AccountBridgeError.invalidResponse
        }
        productID = product; offerID = offer; keyID = key; self.nonce = nonce
        self.signature = signature; self.timestamp = timestamp
        expiresAt = Date(timeIntervalSince1970: expiry / 1_000)
    }

    static func identifier(for plan: SubscriptionProduct) -> String {
        let name: String
        switch plan {
        case .solo: name = "personal"
        case .personal: name = "personal_plus"
        case .studio: name = "fleet"
        }
        return "granttap_\(name)_half_month_v1"
    }
}

@MainActor
enum SubscriptionRetentionAPI {
    static func post(_ path: String, body: [String: Any], session: GrantTapAccountSession? = GrantTapAccountAPI.session,
                     transport: URLSession = .shared,
                     currentSession: () -> GrantTapAccountSession? = { GrantTapAccountAPI.session }) async throws -> [String: Any] {
        guard let session else { throw ManagedSubscriptionError.signIn }
        let result = try await GrantTapAccountAPI.json("subscriptions/\(path)", method: "POST",
            body: body, token: session.token, transport: transport)
        guard currentSession()?.accountId == session.accountId,
              currentSession()?.token == session.token else { throw CancellationError() }
        return result
    }

    static func offer(session: GrantTapAccountSession? = GrantTapAccountAPI.session,
                      transport: URLSession = .shared,
                      currentSession: () -> GrantTapAccountSession? = { GrantTapAccountAPI.session },
                      clock: () -> Date = Date.init) async throws -> SubscriptionRetentionOffer? {
        let response = try await post("cancellation-offer", body: ["intent": "cancel"],
            session: session, transport: transport, currentSession: currentSession)
        if response["offer"] is NSNull { return nil }
        guard let value = response["offer"] as? [String: Any] else { throw AccountBridgeError.invalidResponse }
        return try SubscriptionRetentionOffer(value, now: clock())
    }

    static func feedback(id: UUID, reason: String, comment: String,
                         session: GrantTapAccountSession? = GrantTapAccountAPI.session,
                         transport: URLSession = .shared,
                         currentSession: () -> GrantTapAccountSession? = { GrantTapAccountAPI.session }) async throws {
        let response = try await post("cancellation-feedback", body:
            ["feedbackId": id.uuidString.lowercased(), "reason": reason, "comment": comment],
            session: session, transport: transport, currentSession: currentSession)
        guard response["saved"] as? Bool == true else { throw AccountBridgeError.invalidResponse }
    }
}
