import XCTest
@testable import GrantTap

@MainActor
final class SubscriptionStoreEvidenceTests: XCTestCase {
    func testTransportEvidenceIsReadyBeforeProductDiscovery() async {
        let receipt = SubscriptionStatusSnapshot(product: .solo, state: .subscribed,
            expirationDate: Date().addingTimeInterval(3600), isTrial: false, verified: true)
        var productsRequested = false
        let store = SubscriptionStore(startObserving: false, productLoader: {
            productsRequested = true
            return []
        }, snapshotLoader: { products in
            XCTAssertTrue(products.isEmpty)
            return [receipt]
        }, betaEnvironmentLoader: { false })
        await store.prepareTransport()
        XCTAssertTrue(store.allowsManagedTransport)
        XCTAssertFalse(productsRequested)
        XCTAssertEqual(store.availability, .loading)
    }

    func testVerifiedSandboxAppCanExerciseRelayWithoutClaimingSubscription() async {
        let beta = SubscriptionStore(startObserving: false, productLoader: { [] },
            snapshotLoader: { _ in [] }, betaEnvironmentLoader: { true })
        await beta.start()
        XCTAssertEqual(beta.entitlement, .unavailable)
        XCTAssertTrue(beta.betaRelayAccess)
        XCTAssertTrue(beta.allowsManagedTransport)

        let production = SubscriptionStore(startObserving: false, productLoader: { [] },
            snapshotLoader: { _ in [] }, betaEnvironmentLoader: { false })
        await production.start()
        XCTAssertFalse(production.allowsManagedTransport)
    }

    func testAccountTesterGrantAllowsRelayWhenStoreKitCannotRefresh() async {
        let until = Date().addingTimeInterval(3_600)
        var storeKitRefreshes = 0
        let store = SubscriptionStore(startObserving: false, productLoader: { [] },
            snapshotLoader: { _ in [] }, betaEnvironmentLoader: { false },
            betaEnvironmentRefresh: {
                storeKitRefreshes += 1
                throw URLError(.cannotConnectToHost)
            }, accountBetaLoader: {
                AccountBetaRelayGrant(accountID: "owner", expiresAt: until)
            }, currentAccountID: { "owner" })
        await store.prepareTransport()
        XCTAssertTrue(store.allowsManagedTransport)
        XCTAssertFalse(store.betaRelayAccess)
        XCTAssertEqual(store.entitlement, .unavailable)
        await store.verifyBetaRelayAccess()
        XCTAssertEqual(storeKitRefreshes, 0)
        XCTAssertNil(store.betaVerificationError)
    }

    func testAccountTesterGrantRevocationAndExpiryCloseRelayAccess() async {
        var now = Date()
        var accountID = "owner"
        var grant: AccountBetaRelayGrant? = .init(accountID: accountID,
                                                  expiresAt: now.addingTimeInterval(3_600))
        let store = SubscriptionStore(startObserving: false, productLoader: { [] },
            snapshotLoader: { _ in [] }, betaEnvironmentLoader: { false },
            accountBetaLoader: { grant }, currentAccountID: { accountID }, clock: { now })
        await store.prepareTransport()
        XCTAssertTrue(store.allowsManagedTransport)
        accountID = "other"
        XCTAssertFalse(store.allowsManagedTransport)
        accountID = "owner"
        grant = nil
        now.addTimeInterval(31)
        await store.recheckTransportIfNeeded(now: now)
        XCTAssertFalse(store.allowsManagedTransport)

        grant = .init(accountID: "owner", expiresAt: now.addingTimeInterval(-1))
        await store.refreshBetaRelayAccess()
        XCTAssertFalse(store.allowsManagedTransport)
    }

    func testTransportRechecksStoreKitAfterUnavailableLaunchEvidence() async {
        var checks = 0
        let store = SubscriptionStore(startObserving: false, productLoader: { [] },
            snapshotLoader: { _ in [] }, betaEnvironmentLoader: {
                checks += 1
                return checks > 1
            })
        await store.prepareTransport()
        XCTAssertFalse(store.allowsManagedTransport)
        await store.recheckTransportIfNeeded(now: Date().addingTimeInterval(10))
        XCTAssertEqual(checks, 1)
        await store.recheckTransportIfNeeded(now: Date().addingTimeInterval(31))
        XCTAssertEqual(checks, 2)
        XCTAssertTrue(store.allowsManagedTransport)
    }

    func testExplicitAppVerificationRestoresTestFlightRelayAccess() async {
        var requests = 0
        let store = SubscriptionStore(startObserving: false, productLoader: { [] },
            snapshotLoader: { _ in [] }, betaEnvironmentLoader: { false },
            betaEnvironmentRefresh: {
                requests += 1
                return true
            })
        await store.prepareTransport()
        XCTAssertFalse(store.allowsManagedTransport)
        await store.verifyBetaRelayAccess()
        XCTAssertEqual(requests, 1)
        XCTAssertTrue(store.allowsManagedTransport)
    }

    func testStoreKitRetryFailurePreservesPreviouslyVerifiedRelayAccess() async {
        let store = SubscriptionStore(startObserving: false, productLoader: { [] },
            snapshotLoader: { _ in [] }, betaEnvironmentLoader: { true },
            betaEnvironmentRefresh: { throw URLError(.notConnectedToInternet) })
        await store.prepareTransport()
        await store.verifyBetaRelayAccess()
        XCTAssertTrue(store.allowsManagedTransport)
        XCTAssertNotNil(store.betaVerificationError)
    }

    func testFailedStorefrontDoesNotRevokeVerifiedSandboxTransport() async {
        let store = SubscriptionStore(startObserving: false,
            productLoader: { throw URLError(.notConnectedToInternet) },
            snapshotLoader: { _ in [] }, betaEnvironmentLoader: { true })
        await store.start()
        XCTAssertTrue(store.allowsManagedTransport)
        if case .failed = store.availability { } else { XCTFail("Storefront failure should be visible") }
        XCTAssertNotNil(store.lastError)
    }

    func testManageAndRestoreFailurePreserveVerifiedEntitlement() async {
        let receipt = SubscriptionStatusSnapshot(product: .solo, state: .subscribed,
            expirationDate: Date().addingTimeInterval(3600), isTrial: false, verified: true)
        let store = SubscriptionStore(startObserving: false,
            snapshotLoader: { _ in [receipt] },
            storeSync: { throw URLError(.notConnectedToInternet) },
            manageSubscriptions: { _ in throw URLError(.notConnectedToInternet) })
        await store.refresh()
        await store.manage(in: nil)
        await store.manage()
        XCTAssertTrue(store.allowsManagedTransport)
        XCTAssertNotNil(store.lastError)
        store.clearError()
        XCTAssertNil(store.lastError)
        await store.restore()
        XCTAssertTrue(store.allowsManagedTransport)
        XCTAssertFalse(store.purchaseInProgress)
        XCTAssertNotNil(store.lastError)
    }

    func testMissingOfferDoesNotStartAStorePurchase() async {
        let store = SubscriptionStore(startObserving: false,
            productLoader: { [] }, snapshotLoader: { _ in [] })
        await store.purchase(offerID: "missing-tier")
        XCTAssertFalse(store.purchaseInProgress)
        XCTAssertNotNil(store.lastError)
    }

    func testUnavailableCatalogUsesVerifiedReceiptAndAuthoritativeRevocationStillWins() async {
        let receipt = SubscriptionStatusSnapshot(product: .solo, state: .subscribed,
            expirationDate: Date().addingTimeInterval(3600), isTrial: false, verified: true)
        var statuses: [SubscriptionStatusSnapshot] = []
        var authoritative: Set<SubscriptionProduct> = []
        let store = SubscriptionStore(startObserving: false, productLoader: { [] }, snapshotLoader: { _ in
            SubscriptionStoreEvidence.merge(statuses, authoritative: authoritative, receipts: [receipt])
        })
        await store.start()
        XCTAssertTrue(store.entitlement.state.allowsRemoteInfrastructure)
        XCTAssertEqual(store.entitlement.seatLimit, 2)
        authoritative = [.solo]
        statuses = [.init(product: .solo, state: .revoked, expirationDate: nil, isTrial: false, verified: true)]
        await store.refresh()
        XCTAssertEqual(store.entitlement.state, .revoked)
        XCTAssertFalse(store.entitlement.state.allowsRemoteInfrastructure)
        statuses = []
        await store.refresh()
        XCTAssertEqual(store.entitlement, .unavailable)
    }

    func testExpiredOrUnverifiedReceiptCannotGrantHostedAccess() {
        let now = Date()
        for receipt in [
            SubscriptionStatusSnapshot(product: .personal, state: .subscribed,
                expirationDate: now.addingTimeInterval(-1), isTrial: false, verified: true),
            SubscriptionStatusSnapshot(product: .studio, state: .subscribed,
                expirationDate: now.addingTimeInterval(3600), isTrial: false, verified: false)
        ] {
            let snapshots = SubscriptionStoreEvidence.merge([], authoritative: [], receipts: [receipt])
            XCTAssertFalse(SubscriptionEntitlement.reduce(snapshots, now: now).state.allowsRemoteInfrastructure)
        }
    }

    func testReadFailureDoesNotLeavePreviouslyGrantedSubscription() async {
        var fail = false
        let store = SubscriptionStore(startObserving: false, snapshotLoader: { _ in
            if fail { throw URLError(.notConnectedToInternet) }
            return [.init(product: .solo, state: .subscribed, expirationDate: Date().addingTimeInterval(100),
                isTrial: false, verified: true)]
        })
        await store.refresh()
        XCTAssertTrue(store.entitlement.state.allowsRemoteInfrastructure)
        fail = true
        await store.refresh()
        XCTAssertEqual(store.entitlement, .unavailable)
        XCTAssertNotNil(store.lastError)
    }
}
