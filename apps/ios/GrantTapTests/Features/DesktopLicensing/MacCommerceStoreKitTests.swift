import StoreKit
import StoreKitTest
import XCTest
@testable import GrantTap

@MainActor
final class MacCommerceStoreKitTests: XCTestCase {
    private func session() throws -> SKTestSession {
        guard ProcessInfo.processInfo.environment["GRANTTAP_STOREKIT_TESTS"] == "1" else {
            throw XCTSkip("Run the GrantTap Commerce scheme for isolated StoreKit service testing.")
        }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "MacCommerce", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        return session
    }

    func testActualStoreKitPurchaseSurvivesRestartAndRefundRevokesMacLicense() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let store = DesktopLicenseStore(evaluationAllowed: false, observe: false)
        await store.start()
        XCTAssertEqual(store.license, .notPurchased)
        XCTAssertEqual(store.product?.price, Decimal(string: "39.99"))
        await store.purchase()
        XCTAssertNil(store.lastError)
        XCTAssertEqual(store.license, .purchased)
        let reopened = DesktopLicenseStore(evaluationAllowed: false, observe: false)
        await reopened.start()
        XCTAssertEqual(reopened.license, .purchased)
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.refundTransaction(identifier: transaction.identifier)
        await reopened.refresh()
        XCTAssertEqual(reopened.license, .notPurchased)
    }

    func testSubscriptionReceiptSurvivesUnavailableProductCatalogWithoutGrantingMacLicense() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        try session.buyProduct(productIdentifier: "com.ziborov.granttap.personal.solo.monthly")
        let subscription = SubscriptionStore(startObserving: false,
            productLoader: { throw URLError(.notConnectedToInternet) })
        await subscription.start()
        XCTAssertTrue(subscription.entitlement.state.allowsRemoteInfrastructure)
        XCTAssertEqual(subscription.entitlement.seatLimit, 1)
        let license = DesktopLicenseStore(evaluationAllowed: false, observe: false)
        await license.refresh()
        XCTAssertEqual(license.license, .notPurchased)
    }
}
