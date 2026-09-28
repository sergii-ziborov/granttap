import XCTest
@testable import GrantTap

@MainActor
final class SubscriptionStoreEvidenceTests: XCTestCase {
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
        XCTAssertEqual(store.entitlement.seatLimit, 1)
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
            SubscriptionStatusSnapshot(product: .fleet, state: .subscribed,
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
