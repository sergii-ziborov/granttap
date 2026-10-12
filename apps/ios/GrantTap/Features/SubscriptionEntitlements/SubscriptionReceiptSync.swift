import Foundation
import StoreKit

enum ManagedPurchaseIdentity {
    static func token(for accountID: String?) throws -> UUID {
        guard let accountID, let id = UUID(uuidString: accountID) else {
            throw ManagedSubscriptionError.signIn
        }
        return id
    }
}

enum ManagedSubscriptionError: LocalizedError {
    case signIn, unboundPurchase
    var errorDescription: String? {
        switch self {
        case .signIn: return L("Connect with passkey before subscribing so your computers share the same plan.")
        case .unboundPurchase: return L("This purchase is not linked to this GrantTap account. Use the account that purchased it.")
        }
    }
}

/// Apple verifies the device receipt; the account service verifies its JWS again.
@MainActor
enum SubscriptionReceiptSync {
    static func refresh() async throws {
        guard !AppRuntime.isRunningUnitTests, let session = GrantTapAccountAPI.session else { return }
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  SubscriptionProduct(rawValue: transaction.productID) != nil else { continue }
            if #available(iOS 16.0, macCatalyst 16.0, *), transaction.environment != .production { continue }
            guard transaction.appAccountToken == UUID(uuidString: session.accountId) else {
                throw ManagedSubscriptionError.unboundPurchase
            }
            try await upload(result.jwsRepresentation, session: session)
        }
    }

    static func upload(_ signedTransaction: String, session: GrantTapAccountSession,
                       transport: URLSession = .shared,
                       currentSession: () -> GrantTapAccountSession? = { GrantTapAccountAPI.session }) async throws {
        guard currentSession()?.accountId == session.accountId,
              currentSession()?.token == session.token else { throw CancellationError() }
        let response = try await GrantTapAccountAPI.json("subscriptions/receipt", method: "POST",
            body: ["signedTransaction": signedTransaction], token: session.token, transport: transport)
        guard currentSession()?.token == session.token else { throw CancellationError() }
        guard response["accepted"] as? Bool == true || response["entitlement"] is [String: Any] else {
            throw ManagedSubscriptionError.unboundPurchase
        }
    }
}
