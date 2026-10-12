import Foundation

struct AccountBetaRelayGrant: Equatable {
    let accountID: String
    let expiresAt: Date
}

/// The account server returns only the grant belonging to its verified session.
enum AccountBetaRelayGrantAPI {
    static func load(session: GrantTapAccountSession? = GrantTapAccountAPI.session,
                     transport: URLSession = .shared,
                     currentSession: () -> GrantTapAccountSession? = { GrantTapAccountAPI.session })
        async throws -> AccountBetaRelayGrant? {
        guard let session else { return nil }
        let response = try await GrantTapAccountAPI.json("beta-relay", token: session.token,
                                                         transport: transport)
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
