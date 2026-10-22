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

    func testStoreCatalogOffersMacLocalAndThreeMonthlyPlans() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let ids = [DesktopLicense.productID] + SubscriptionProduct.allCases.map(\.rawValue)
        let products = try await Product.products(for: ids)
        XCTAssertEqual(Set(products.map(\.id)), Set(ids))
        let prices = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0.price) })
        XCTAssertEqual(prices[DesktopLicense.productID], Decimal(string: "39.99"))
        XCTAssertEqual(prices[SubscriptionProduct.solo.rawValue], Decimal(string: "4.99"))
        XCTAssertEqual(prices[SubscriptionProduct.personal.rawValue], Decimal(string: "7.99"))
        XCTAssertEqual(prices[SubscriptionProduct.studio.rawValue], Decimal(string: "13.99"))
    }

    func testSevenDayTrialUsesStoreKitEligibilityAndDoesNotRestartAfterPurchase() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let store = SubscriptionStore(startObserving: false,
            currentAccountID: { "12345678-1234-4123-8123-123456789012" })
        await store.loadProducts()
        XCTAssertEqual(store.offers.filter(\.hasSevenDayTrial).count, 3)
        await store.purchase(offerID: SubscriptionProduct.solo.rawValue)
        XCTAssertNil(store.lastError)
        guard case .trial(let expires) = store.entitlement.state else {
            XCTFail("An Apple trial receipt must be represented as a trial")
            return
        }
        XCTAssertGreaterThan(expires.timeIntervalSinceNow, 6 * 86_400)
        await store.loadProducts()
        XCTAssertTrue(store.offers.allSatisfy { !$0.hasSevenDayTrial })
        let reopened = SubscriptionStore(startObserving: false)
        await reopened.refresh()
        XCTAssertEqual(reopened.entitlement.state, .trial(expiresAt: expires))
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
        let reopened = DesktopLicenseStore(evaluationAllowed: false, observe: true)
        await reopened.start()
        XCTAssertEqual(reopened.license, .purchased)
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.refundTransaction(identifier: transaction.identifier)
        // StoreKit delivers revocation through Transaction.updates asynchronously.
        // Exercise the production observer instead of reading the old cached receipt.
        let deadline = Date().addingTimeInterval(5)
        while reopened.license != .notPurchased && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
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
        XCTAssertEqual(subscription.entitlement.seatLimit, 2)
        let license = DesktopLicenseStore(evaluationAllowed: false, observe: false)
        await license.refresh()
        XCTAssertEqual(license.license, .notPurchased)
    }
}
