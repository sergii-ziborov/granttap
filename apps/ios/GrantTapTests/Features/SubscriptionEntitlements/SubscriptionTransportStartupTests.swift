import XCTest
@testable import GrantTap

@MainActor
final class SubscriptionTransportStartupTests: XCTestCase {
    func testVerifiedAccountTransportDoesNotWaitForStoreKit() async {
        var appTransactionReads = 0
        var receiptReads = 0
        let store = SubscriptionStore(startObserving: false, snapshotLoader: { _ in
            receiptReads += 1
            return []
        }, betaEnvironmentLoader: {
            appTransactionReads += 1
            return false
        }, accountBetaLoader: {
            AccountBetaRelayGrant(accountID: "tester", expiresAt: Date().addingTimeInterval(3_600))
        }, currentAccountID: { "tester" })

        await store.prepareTransport()

        XCTAssertTrue(store.allowsManagedTransport)
        XCTAssertEqual(appTransactionReads, 0, "Verified account access must not wait for StoreKit")
        XCTAssertEqual(receiptReads, 0, "Receipt discovery must not delay an authorized connection")
        XCTAssertEqual(store.entitlement, .unavailable)
    }

    func testVerifiedSandboxTransportDoesNotWaitForReceiptDiscovery() async {
        var receiptReads = 0
        let store = SubscriptionStore(startObserving: false, snapshotLoader: { _ in
            receiptReads += 1
            return []
        }, betaEnvironmentLoader: { true }, accountBetaLoader: { nil })

        await store.prepareTransport()

        XCTAssertTrue(store.betaRelayAccess)
        XCTAssertTrue(store.allowsManagedTransport)
        XCTAssertEqual(receiptReads, 0)
        XCTAssertEqual(store.entitlement, .unavailable)
    }

    func testUnverifiedAccountStillRequiresVerifiedStoreEvidence() async {
        var receiptReads = 0
        let store = SubscriptionStore(startObserving: false, snapshotLoader: { _ in
            receiptReads += 1
            return []
        }, betaEnvironmentLoader: { false }, accountBetaLoader: {
            AccountBetaRelayGrant(accountID: "another-account", expiresAt: Date().addingTimeInterval(3_600))
        }, currentAccountID: { "tester" })

        await store.prepareTransport()

        XCTAssertFalse(store.allowsManagedTransport)
        XCTAssertEqual(receiptReads, 1)
    }
}
