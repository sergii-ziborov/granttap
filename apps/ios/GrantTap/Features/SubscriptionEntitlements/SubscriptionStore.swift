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

    @Published private(set) var products: [Product] = []
    @Published private(set) var entitlement: SubscriptionEntitlement = .unavailable
    @Published private(set) var betaRelayAccess = false
    @Published private(set) var availability: Availability = .loading
    @Published private(set) var purchaseInProgress = false
    @Published private(set) var lastError: String?

    /// Tiers the store returned, smallest first, so the paywall reads as a ladder.
    var offers: [SubscriptionOffer] {
        products
            .map {
                SubscriptionOffer(
                    id: $0.id, displayName: $0.displayName, displayPrice: $0.displayPrice
                )
            }
            .sorted { $0.seatLimit < $1.seatLimit }
    }

    private var observer: Task<Void, Never>?
    private let productLoader: ProductLoader
    private let snapshotLoader: SnapshotLoader
    private let betaEnvironmentLoader: () async -> Bool
    private let storeSync: StoreSync
    private let manageSubscriptions: ManageSubscriptions

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
            guard !AppRuntime.isRunningUnitTests else { return false }
            guard #available(iOS 16.0, macCatalyst 16.0, *) else { return false }
            guard let result = try? await AppTransaction.shared,
                  case .verified(let transaction) = result else { return false }
            return transaction.environment == .sandbox
        },
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
        self.storeSync = storeSync
        self.manageSubscriptions = manageSubscriptions
        if startObserving {
            observer = Task { [weak self] in
                for await _ in Transaction.updates {
                    guard !Task.isCancelled else { return }
                    await self?.refresh()
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
        await refreshBetaRelayAccess()
        await refresh()
    }

    func loadStorefront() async {
        await loadProducts()
        await refresh()
    }

    var allowsManagedTransport: Bool {
        betaRelayAccess || entitlement.state.allowsRemoteInfrastructure
    }

    func refreshBetaRelayAccess() async {
        betaRelayAccess = await betaEnvironmentLoader()
    }

    func loadProducts() async {
        availability = .loading
        do {
            products = try await productLoader()
                .filter { SubscriptionProduct(rawValue: $0.id) != nil }
            availability = products.isEmpty ? .notConfigured : .ready
            lastError = nil
        } catch {
            products = []
            availability = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func refresh() async {
        do {
            entitlement = SubscriptionEntitlement.reduce(try await snapshotLoader(products), now: Date())
        } catch {
            entitlement = .unavailable
            lastError = error.localizedDescription
        }
    }

    func purchase(_ product: Product) async {
        purchaseInProgress = true
        defer { purchaseInProgress = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refresh()
                lastError = nil
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
        defer { purchaseInProgress = false }
        do {
            try await storeSync()
            await refresh()
            lastError = nil
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
