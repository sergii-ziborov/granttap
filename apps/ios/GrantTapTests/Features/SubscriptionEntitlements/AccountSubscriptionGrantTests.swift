import Foundation
import XCTest
@testable import GrantTap

@MainActor
final class AccountSubscriptionGrantTests: XCTestCase {
    func testPurchaseOnPhoneAuthorizesSameAccountWithoutMacTrialOrStoreKitLookup() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var account = "owner"
        var receiptReads = 0
        let right = SubscriptionEntitlement(state: .trial(expiresAt: now.addingTimeInterval(604_800)),
            product: .solo, seatLimit: 2)
        let grant = AccountSubscriptionGrant(accountID: account, entitlement: right,
            validatedUntil: now.addingTimeInterval(300))
        let store = SubscriptionStore(startObserving: false, snapshotLoader: { _ in
            receiptReads += 1
            return []
        }, betaEnvironmentLoader: { false }, accountBetaLoader: { nil },
        accountSubscriptionLoader: { grant }, currentAccountID: { account }, clock: { now })
        await store.prepareTransport()
        XCTAssertTrue(store.accountSubscriptionAllowsTransport)
        XCTAssertEqual(store.effectiveEntitlement, right)
        XCTAssertEqual(receiptReads, 0)
        account = "another-owner"
        XCTAssertFalse(store.allowsManagedTransport)
        XCTAssertEqual(store.effectiveEntitlement, .unavailable)
        XCTAssertFalse(grant.allowsTransport(accountID: "owner", now: now.addingTimeInterval(300)))
    }

    func testServerRevocationClearsSharedAccessAndNetworkFailureCannotExtendLease() async {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var fail = false
        let grant = AccountSubscriptionGrant(accountID: "owner", entitlement:
            SubscriptionEntitlement(state: .active(expiresAt: now.addingTimeInterval(604_800)),
                product: .personal, seatLimit: 5), validatedUntil: now.addingTimeInterval(300))
        var response: AccountSubscriptionGrant? = grant
        let store = SubscriptionStore(startObserving: false, betaEnvironmentLoader: { false },
            accountBetaLoader: { nil }, accountSubscriptionLoader: {
                if fail { throw URLError(.notConnectedToInternet) }
                return response
            }, currentAccountID: { "owner" }, clock: { now })
        await store.prepareTransport()
        fail = true
        await store.refreshAccountSubscription()
        XCTAssertTrue(store.allowsManagedTransport)
        now = now.addingTimeInterval(301)
        await store.refreshAccountSubscription()
        XCTAssertFalse(store.allowsManagedTransport)
        fail = false
        now = now.addingTimeInterval(-301)
        response = grant
        await store.refreshAccountSubscription()
        response = nil
        await store.refreshAccountSubscription()
        XCTAssertFalse(store.allowsManagedTransport)
    }

    func testHTTPGrantRequiresAccountSessionAndValidProductCapacity() async throws {
        let session = GrantTapAccountSession(accountId: "owner", token: String(repeating: "A", count: 43))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountSubscriptionURLProtocol.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel() }
        let valid: [String: Any] = ["source": "subscription", "productId": SubscriptionProduct.solo.rawValue,
            "limit": 2, "expiresAt": 2_000_000_000_000,
            "validatedUntil": Date().addingTimeInterval(300).timeIntervalSince1970 * 1_000, "isTrial": true]
        func payload(_ value: Any) throws {
            AccountSubscriptionURLProtocol.payload = try JSONSerialization.data(withJSONObject: ["entitlement": value])
        }
        try payload(valid)
        let grant = try await AccountSubscriptionGrantAPI.load(session: session,
            transport: transport, currentSession: { session })
        XCTAssertEqual(AccountSubscriptionURLProtocol.path, "/api/account/subscriptions/entitlement")
        XCTAssertTrue(AccountSubscriptionURLProtocol.authorized)
        XCTAssertEqual(grant?.entitlement.state, .trial(expiresAt: Date(timeIntervalSince1970: 2_000_000_000)))
        let absentValues: [Any] = [NSNull(), ["source": "beta"]]
        for value in absentValues {
            try payload(value)
            let absent = try await AccountSubscriptionGrantAPI.load(session: session,
                transport: transport, currentSession: { session })
            XCTAssertNil(absent)
        }
        let invalidValues: [Any] = ["malformed", ["source": "unknown"],
            valid.merging(["limit": 100]) { _, new in new },
            valid.merging(["validatedUntil": Date().addingTimeInterval(600).timeIntervalSince1970 * 1_000]) { _, new in new },
            valid.merging(["validatedUntil": 3_000_000_000_000]) { _, new in new }]
        for value in invalidValues {
            try payload(value)
            do {
                _ = try await AccountSubscriptionGrantAPI.load(session: session,
                    transport: transport, currentSession: { session })
                XCTFail("Invalid server rights must not authorize a computer")
            } catch { XCTAssertTrue(error is AccountBridgeError) }
        }
        try payload(valid)
        do {
            _ = try await AccountSubscriptionGrantAPI.load(session: session,
                transport: transport, currentSession: { nil })
            XCTFail("Changed sessions must not inherit paid access")
        } catch { XCTAssertTrue(error is CancellationError) }
        let signedOut = try await AccountSubscriptionGrantAPI.load(session: nil,
            transport: transport, currentSession: { nil })
        XCTAssertNil(signedOut)
    }
}

private final class AccountSubscriptionURLProtocol: URLProtocol {
    static var payload = Data()
    static var path: String?
    static var authorized = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.path = request.url?.path
        Self.authorized = request.value(forHTTPHeaderField: "Authorization") != nil
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
