#if DEBUG
import Foundation

/// Isolated storefront presentation; no StoreKit purchase or account request runs.
@MainActor
enum SandboxSubscriptionFixture {
    struct Configuration {
        let store: SubscriptionStore
        let offers: [SubscriptionOffer]
    }

    static func configuration() -> Configuration? {
        guard let mode = ProcessInfo.processInfo.environment["GRANTTAP_TEST_SANDBOX_PURCHASES"],
              ["sandbox", "account"].contains(mode) else { return nil }
        let account = "12345678-1234-4123-8123-123456789012"
        let grant = mode == "account"
            ? AccountBetaRelayGrant(accountID: account, expiresAt: Date().addingTimeInterval(3_600)) : nil
        let store = SubscriptionStore(startObserving: false,
            productLoader: { [] }, snapshotLoader: { _ in [] },
            betaEnvironmentLoader: { mode == "sandbox" },
            accountBetaLoader: { grant }, accountSubscriptionLoader: { nil },
            currentAccountID: { mode == "account" ? account : nil })
        store.betaRelayAccess = mode == "sandbox"
        store.accountBetaGrant = grant
        let offers = zip(SubscriptionProduct.ordered, ["$4.99", "$7.99", "$13.99"]).map {
            SubscriptionOffer(id: $0.0.rawValue, displayName: $0.0.summary,
                displayPrice: $0.1, hasSevenDayTrial: true)
        }
        return Configuration(store: store, offers: offers)
    }
}
#endif
