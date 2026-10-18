import Foundation

struct AccountBetaRelayGrant: Equatable {
    let accountID: String
    let expiresAt: Date
}

/// The account server returns only the grant belonging to its verified session.
enum AccountBetaRelayGrantAPI {
    static func load(session: GrantTapAccountSession? = GrantTapAccountAPI.session,
                     transport: URLSession = .shared,
                     currentSession: () -> GrantTapAccountSession? = { GrantTapAccountAPI.session },
                     betaEvidence: () async -> String? = { await TestFlightAccessStore.signedEvidence() })
        async throws -> AccountBetaRelayGrant? {
        guard let session else { return nil }
        var response = try await GrantTapAccountAPI.json("beta-relay", token: session.token,
                                                         transport: transport)
        let expired = (response["expiresAt"] as? Double).map {
            $0.isFinite && $0 > 0 && $0 <= Date().timeIntervalSince1970 * 1_000
        } ?? false
        if response["expiresAt"] is NSNull || expired, let proof = await betaEvidence() {
            guard currentSession()?.token == session.token else { throw CancellationError() }
            response = try await GrantTapAccountAPI.json("subscriptions/testflight", method: "POST",
                body: ["signedAppTransaction": proof], token: session.token, transport: transport)
        }
        guard currentSession()?.token == session.token else {
            throw CancellationError()
        }
        guard let value = response["expiresAt"] else {
            throw AccountBridgeError.invalidResponse
        }
        if value is NSNull { return nil }
        guard let milliseconds = value as? Double,
              milliseconds.isFinite, milliseconds > 0 else {
            throw AccountBridgeError.invalidResponse
        }
        return AccountBetaRelayGrant(accountID: session.accountId,
                                     expiresAt: Date(timeIntervalSince1970: milliseconds / 1_000))
    }
}
