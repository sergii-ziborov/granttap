import Foundation

/// A short server authorization for a purchase made on any client of this account.
struct AccountSubscriptionGrant: Equatable {
    let accountID: String
    let entitlement: SubscriptionEntitlement
    let validatedUntil: Date

    func allowsTransport(accountID: String?, now: Date) -> Bool {
        self.accountID == accountID && validatedUntil > now
            && entitlement.state.allowsRemoteInfrastructure
    }
}

enum AccountSubscriptionGrantAPI {
    static func load(session: GrantTapAccountSession? = GrantTapAccountAPI.session,
                     transport: URLSession = .shared,
                     currentSession: () -> GrantTapAccountSession? = { GrantTapAccountAPI.session },
                     clock: () -> Date = Date.init)
        async throws -> AccountSubscriptionGrant? {
        guard let session else { return nil }
        let response = try await GrantTapAccountAPI.json("subscriptions/entitlement",
            token: session.token, transport: transport)
        guard currentSession()?.token == session.token,
              currentSession()?.accountId == session.accountId else { throw CancellationError() }
        guard let value = response["entitlement"] else { throw AccountBridgeError.invalidResponse }
        if value is NSNull { return nil }
        guard let entry = value as? [String: Any] else { throw AccountBridgeError.invalidResponse }
        if entry["source"] as? String == "beta" { return nil }
        guard entry["source"] as? String == "subscription",
              let id = entry["productId"] as? String, let product = SubscriptionProduct(rawValue: id),
              entry["limit"] as? Int == product.seatLimit,
              let expires = entry["expiresAt"] as? Double, expires.isFinite, expires > 0,
              let validated = entry["validatedUntil"] as? Double, validated.isFinite,
              validated > 0, validated <= expires,
              validated <= clock().timeIntervalSince1970 * 1_000 + 360_000
              else { throw AccountBridgeError.invalidResponse }
        let expiry = Date(timeIntervalSince1970: expires / 1_000)
        let trial = entry["isTrial"] as? Bool == true
        let entitlement = SubscriptionEntitlement(
            state: trial ? .trial(expiresAt: expiry) : .active(expiresAt: expiry),
            product: product, seatLimit: product.seatLimit)
        return AccountSubscriptionGrant(accountID: session.accountId, entitlement: entitlement,
            validatedUntil: Date(timeIntervalSince1970: validated / 1_000))
    }
}
