import XCTest
import Combine
@testable import GrantTap

@MainActor
final class SubscriptionTransportStartupTests: XCTestCase {
    func testRenewedAccessEvidenceKeepsTheSameConnectionUntilAccessChanges() async {
        let store = SubscriptionStore(startObserving: false, snapshotLoader: { _ in [] },
            betaEnvironmentLoader: { false }, accountBetaLoader: { nil },
            accountSubscriptionLoader: { nil }, currentAccountID: { "tester" })
        var reconnects = 0
        let subscription = store.transportAccessChanges.sink { reconnects += 1 }
        XCTAssertEqual(reconnects, 0, "Reading initial evidence must not reopen transport")
        store.accountBetaGrant = .init(accountID: "tester", expiresAt: Date().addingTimeInterval(300))
        XCTAssertEqual(reconnects, 1)
        store.accountBetaGrant = .init(accountID: "tester", expiresAt: Date().addingTimeInterval(600))
        await store.refresh()
        XCTAssertEqual(reconnects, 1, "Renewed permission and unrelated receipt evidence keep the socket")
        store.accountBetaGrant = nil
        XCTAssertEqual(reconnects, 2, "Revocation must revalidate the network route")
        store.betaRelayAccess = true
        XCTAssertEqual(reconnects, 3)
        withExtendedLifetime(subscription) {}
    }

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
        XCTAssertLessThanOrEqual(appTransactionReads, 1, "Local distribution evidence is checked concurrently without prompting")
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

    func testTestFlightUnlockDoesNotCreateOrStartASubscriptionTrial() async {
        let store = SubscriptionStore(startObserving: false, snapshotLoader: { _ in [] },
            betaEnvironmentLoader: { true }, accountBetaLoader: { nil },
            accountSubscriptionLoader: { nil })
        await store.prepareTransport()
        XCTAssertTrue(store.hasTestingAccess)
        XCTAssertTrue(store.allowsManagedTransport)
        XCTAssertEqual(store.effectiveEntitlement, .unavailable)
        await store.refresh()
        XCTAssertTrue(store.hasTestingAccess)
        XCTAssertNil(store.effectiveEntitlement.product)
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
