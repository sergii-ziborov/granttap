import XCTest
import StoreKit
import SwiftUI
import UIKit
@testable import GrantTap

final class SubscriptionEntitlementTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    func testVerifiedTrialAllowsRemoteInfrastructureWithPersonalSeatLimit() {
        let expiry = now.addingTimeInterval(7 * 86_400)
        let result = SubscriptionEntitlement.reduce([
            snapshot(.subscribed, expiry: expiry, trial: true),
        ], now: now)

        XCTAssertEqual(result.state, .trial(expiresAt: expiry))
        XCTAssertEqual(result.seatLimit, SubscriptionProduct.personal.seatLimit)
        XCTAssertTrue(result.state.allowsRemoteInfrastructure)
    }

    func testActiveAndGraceAllowWhileRetryExpiredRevokedAndUnavailableDeny() {
        let future = now.addingTimeInterval(60)
        let allowed: [SubscriptionStatusSnapshot.State] = [.subscribed, .gracePeriod]
        let denied: [SubscriptionStatusSnapshot.State] = [.billingRetry, .expired, .revoked]

        for state in allowed {
            let result = SubscriptionEntitlement.reduce([snapshot(state, expiry: future)], now: now)
            XCTAssertTrue(result.state.allowsRemoteInfrastructure, "\(state)")
        }
        for state in denied {
            let result = SubscriptionEntitlement.reduce([snapshot(state, expiry: future)], now: now)
            XCTAssertFalse(result.state.allowsRemoteInfrastructure, "\(state)")
        }
        XCTAssertFalse(SubscriptionEntitlement.unavailable.state.allowsRemoteInfrastructure)
    }

    func testUnverifiedRecordsNeverGrantAccessAndExpiredSubscribedRecordFailsClosed() {
        let future = now.addingTimeInterval(60)
        let unverified = snapshot(.subscribed, expiry: future, verified: false)
        XCTAssertEqual(SubscriptionEntitlement.reduce([unverified], now: now), .unavailable)

        let expired = snapshot(.subscribed, expiry: now.addingTimeInterval(-1))
        XCTAssertEqual(SubscriptionEntitlement.reduce([expired], now: now).state, .expired)
    }

    func testReducerPrefersUsableVerifiedEntitlement() {
        let future = now.addingTimeInterval(60)
        let result = SubscriptionEntitlement.reduce([
            snapshot(.revoked, expiry: nil),
            snapshot(.billingRetry, expiry: future),
            snapshot(.gracePeriod, expiry: future),
        ], now: now)
        XCTAssertEqual(result.state, .gracePeriod(expiresAt: future))
    }

    @MainActor
    func testStoreLoadsRestoresAndReportsInjectedFailures() async {
        var syncCount = 0
        let store = SubscriptionStore(
            startObserving: false,
            productLoader: { [] },
            storeSync: { syncCount += 1 }
        )
        await store.start()
        XCTAssertEqual(store.availability, .notConfigured)
        XCTAssertEqual(store.entitlement, .unavailable)
        await store.restore()
        XCTAssertEqual(syncCount, 1)
        XCTAssertNil(store.lastError)
        XCTAssertFalse(store.purchaseInProgress)

        let failed = SubscriptionStore(
            startObserving: false,
            productLoader: { throw SubscriptionFixtureError.offline },
            storeSync: { throw SubscriptionFixtureError.offline }
        )
        await failed.loadProducts()
        guard case .failed = failed.availability else {
            return XCTFail("Expected failed StoreKit availability")
        }
        await failed.restore()
        XCTAssertNotNil(failed.lastError)
        await failed.manage(in: nil)
        XCTAssertTrue(failed.lastError?.contains("foreground") == true)
    }

    @MainActor
    func testStoreKitRenewalStatesMapToBoundedSnapshots() {
        let states: [(Product.SubscriptionInfo.RenewalState,
                      SubscriptionStatusSnapshot.State)] = [
            (.subscribed, .subscribed),
            (.inGracePeriod, .gracePeriod),
            (.inBillingRetryPeriod, .billingRetry),
            (.expired, .expired),
            (.revoked, .revoked),
        ]
        for (renewal, expected) in states {
            let result = SubscriptionStore.snapshot(
                product: .personal, renewalState: renewal,
                expirationDate: now, isTrial: true, verified: true
            )
            XCTAssertEqual(result.state, expected)
            XCTAssertEqual(result.expirationDate, now)
            XCTAssertTrue(result.isTrial)
            XCTAssertTrue(result.verified)
        }
        let rejected = SubscriptionStore.snapshot(
            product: .personal, renewalState: .subscribed,
            expirationDate: now, isTrial: true, verified: false
        )
        XCTAssertFalse(rejected.verified)
        XCTAssertFalse(rejected.isTrial)
        XCTAssertNil(rejected.expirationDate)
    }

    @MainActor
    func testPersonalOfferRendersAndMissingStorefrontProductFailsClosed() async {
        let store = SubscriptionStore(startObserving: false)
        let offer = SubscriptionOffer(
            id: SubscriptionProduct.personal.rawValue,
            displayName: "GrantTap Personal",
            displayPrice: "$4.99"
        )
        XCTAssertEqual(offer.id, SubscriptionProduct.personal.rawValue)
        await store.purchase(offerID: offer.id)
        XCTAssertNotNil(store.lastError)
        store.clearError()

        let view = SubscriptionView(store: store, offers: [offer])
        let controller = UIHostingController(rootView: view.productRow(offer))
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        controller.view.layoutIfNeeded()
        XCTAssertNotNil(controller.view)

        let fullController = UIHostingController(rootView: view)
        fullController.loadViewIfNeeded()
        fullController.view.frame = controller.view.frame
        fullController.view.layoutIfNeeded()
        XCTAssertNotNil(fullController.view)
        view.subscribe(offer)
        await Task.yield()
        XCTAssertNotNil(store.lastError)
    }

    private func snapshot(
        _ state: SubscriptionStatusSnapshot.State,
        expiry: Date?,
        trial: Bool = false,
        verified: Bool = true
    ) -> SubscriptionStatusSnapshot {
        SubscriptionStatusSnapshot(product: .personal, state: state,
                                   expirationDate: expiry, isTrial: trial,
                                   verified: verified)
    }
}

private enum SubscriptionFixtureError: Error { case offline }
