import Foundation
import StoreKit
import UIKit

@MainActor
final class SubscriptionStore: ObservableObject {
    static let shared = SubscriptionStore()

    typealias ProductLoader = () async throws -> [Product]
    typealias SnapshotLoader = ([Product]) async throws -> [SubscriptionStatusSnapshot]
    typealias StoreSync = () async throws -> Void
    typealias ManageSubscriptions = (UIWindowScene) async throws -> Void

    enum Availability: Equatable {
        case loading, ready, notConfigured, failed(String)
    }

    @Published var products: [Product] = []
    @Published private(set) var entitlement: SubscriptionEntitlement = .unavailable
    @Published var betaRelayAccess = false
    @Published var accountBetaGrant: AccountBetaRelayGrant?
    @Published var accountSubscriptionGrant: AccountSubscriptionGrant?
    @Published var betaVerificationError: String?
    @Published var availability: Availability = .loading
    @Published private(set) var purchaseInProgress = false
    @Published var trialEligibleProductIDs: Set<String> = []
    @Published var lastError: String?

    private var observer: Task<Void, Never>?
    let productLoader: ProductLoader
    private let snapshotLoader: SnapshotLoader
    let betaEnvironmentLoader: () async -> Bool
    let betaEnvironmentRefresh: () async throws -> Bool
    let accountBetaLoader: () async throws -> AccountBetaRelayGrant?
    let accountSubscriptionLoader: () async throws -> AccountSubscriptionGrant?
    let currentAccountID: () -> String?
    let clock: () -> Date
    private let storeSync: StoreSync
    private let manageSubscriptions: ManageSubscriptions
    var lastTransportCheckAt: Date?
    var transportReadiness: Task<Bool, Never>?
    var transportRevalidation: Task<Void, Never>?

    init(
        startObserving: Bool = !AppRuntime.isRunningUnitTests,
        entitlement: SubscriptionEntitlement = .unavailable,
        availability: Availability = .loading,
        lastError: String? = nil,
        productLoader: @escaping ProductLoader = {
            try await Product.products(for: SubscriptionProduct.allCases.map(\.rawValue))
        },
        snapshotLoader: @escaping SnapshotLoader = { await SubscriptionStoreEvidence.load($0) },
        betaEnvironmentLoader: @escaping () async -> Bool = {
            await TestFlightAccessStore.current()
        },
        betaEnvironmentRefresh: @escaping () async throws -> Bool = {
            try await TestFlightAccessStore.refresh()
        },
        accountBetaLoader: @escaping () async throws -> AccountBetaRelayGrant? = {
            try await AccountBetaRelayGrantAPI.load()
        },
        accountSubscriptionLoader: @escaping () async throws -> AccountSubscriptionGrant? = {
            guard !AppRuntime.isRunningUnitTests else { return nil }
            return try await AccountSubscriptionGrantAPI.load()
        },
        currentAccountID: @escaping () -> String? = { GrantTapAccountAPI.session?.accountId },
        clock: @escaping () -> Date = Date.init,
        storeSync: @escaping StoreSync = { try await AppStore.sync() },
        manageSubscriptions: @escaping ManageSubscriptions = {
            try await AppStore.showManageSubscriptions(in: $0)
        }
    ) {
        self.entitlement = entitlement
        self.availability = availability
        self.lastError = lastError
        self.productLoader = productLoader
        self.snapshotLoader = snapshotLoader
        self.betaEnvironmentLoader = betaEnvironmentLoader
        self.betaEnvironmentRefresh = betaEnvironmentRefresh
        self.accountBetaLoader = accountBetaLoader
        self.accountSubscriptionLoader = accountSubscriptionLoader
        self.currentAccountID = currentAccountID
        self.clock = clock
        self.storeSync = storeSync
        self.manageSubscriptions = manageSubscriptions
        if startObserving {
            observer = Task { [weak self] in
                for await result in Transaction.updates {
                    guard !Task.isCancelled else { return }
                    await self?.refresh()
                    if case .verified(let transaction) = result,
                       SubscriptionProduct(rawValue: transaction.productID) != nil {
                        await transaction.finish()
                    }
                }
            }
        }
    }

    deinit { observer?.cancel() }

    func start() async {
        await prepareTransport()
        await loadStorefront()
    }

    /// Relay routing must wait for verified access, not product discovery.
    func prepareTransport() async {
        _ = await connectionTransportAccess()
    }

    func loadStorefront() async {
        await loadProducts()
        await refresh()
    }

    var accountGrantAllowsTransport: Bool {
        accountBetaGrant.map {
            $0.accountID == currentAccountID() && $0.expiresAt > clock()
        } ?? false
    }

    var allowsManagedTransport: Bool {
        betaRelayAccess || accountGrantAllowsTransport || accountSubscriptionAllowsTransport
            || entitlement.state.allowsRemoteInfrastructure
    }

    var accountSubscriptionAllowsTransport: Bool {
        accountSubscriptionGrant?.allowsTransport(accountID: currentAccountID(), now: clock()) == true
    }

    var effectiveEntitlement: SubscriptionEntitlement {
        accountSubscriptionAllowsTransport ? accountSubscriptionGrant!.entitlement : entitlement
    }

    func refresh() async {
        do {
            entitlement = SubscriptionEntitlement.reduce(try await snapshotLoader(products), now: Date())
        } catch {
            entitlement = .unavailable
            lastError = error.localizedDescription
        }
        do { try await SubscriptionReceiptSync.refresh() }
        catch { lastError = error.localizedDescription }
        await refreshAccountSubscription()
    }

    func purchase(_ product: Product, additionalOptions: Set<Product.PurchaseOption> = []) async {
        purchaseInProgress = true
        lastError = nil
        defer { purchaseInProgress = false }
        do {
            let accountToken = try ManagedPurchaseIdentity.token(for: currentAccountID())
            switch try await product.purchase(options: additionalOptions.union([.appAccountToken(accountToken)])) {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refresh()
            case .success(.unverified):
                lastError = L("The App Store could not verify this purchase.")
            case .pending:
                lastError = L("Purchase is pending approval or payment confirmation.")
            case .userCancelled:
                lastError = nil
            @unknown default:
                lastError = L("The App Store returned an unknown purchase result.")
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func purchase(offerID: String) async {
        guard let product = products.first(where: { $0.id == offerID }) else {
            lastError = L("This subscription is no longer available in the current storefront.")
            return
        }
        await purchase(product)
    }

    func restore() async {
        purchaseInProgress = true
        lastError = nil
        defer { purchaseInProgress = false }
        do {
            try await storeSync()
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func manage() async {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first
        await manage(in: scene)
    }

    func manage(in scene: UIWindowScene?) async {
        guard let scene else {
            lastError = L("Open GrantTap in the foreground to manage subscriptions.")
            return
        }
        do {
            try await manageSubscriptions(scene)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearError() { lastError = nil }

    static func snapshot(
        _ status: Product.SubscriptionInfo.Status,
        product: SubscriptionProduct
    ) -> SubscriptionStatusSnapshot {
        guard case .verified(let transaction) = status.transaction,
              case .verified = status.renewalInfo else {
            return snapshot(product: product, renewalState: .expired,
                            expirationDate: nil, isTrial: false, verified: false)
        }
        return snapshot(
            product: product, renewalState: status.state,
            expirationDate: transaction.expirationDate,
            isTrial: transaction.offerType == .introductory
                && transaction.offerPaymentModeStringRepresentation == "FREE_TRIAL",
            verified: true
        )
    }

    static func snapshot(
        product: SubscriptionProduct,
        renewalState: Product.SubscriptionInfo.RenewalState,
        expirationDate: Date?,
        isTrial: Bool,
        verified: Bool
    ) -> SubscriptionStatusSnapshot {
        guard verified else {
            return SubscriptionStatusSnapshot(product: product, state: .expired,
                                              expirationDate: nil, isTrial: false,
                                              verified: false)
        }
        let state: SubscriptionStatusSnapshot.State
        switch renewalState {
        case .subscribed: state = .subscribed
        case .inGracePeriod: state = .gracePeriod
        case .inBillingRetryPeriod: state = .billingRetry
        case .expired: state = .expired
        case .revoked: state = .revoked
        default: state = .expired
        }
        return SubscriptionStatusSnapshot(
            product: product,
            state: state,
            expirationDate: expirationDate,
            isTrial: isTrial,
            verified: true
        )
    }
}
