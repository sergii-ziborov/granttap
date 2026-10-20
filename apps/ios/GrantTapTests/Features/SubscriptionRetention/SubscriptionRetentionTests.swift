import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class SubscriptionRetentionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var value: [String: Any] {
        ["productId": SubscriptionProduct.solo.rawValue,
         "offerId": "granttap_personal_half_month_v1", "keyId": "fixture", "nonce": UUID().uuidString,
         "signature": Data([1, 2, 3]).base64EncodedString(), "timestamp": 1_800_000_000_000,
         "expiresAt": 1_800_003_600_000.0]
    }

    func testOfferBindsTheKnownTierAndHasBoundedFreshness() throws {
        let offer = try SubscriptionRetentionOffer(value, now: now)
        XCTAssertEqual(offer.productID, SubscriptionProduct.solo.rawValue)
        XCTAssertEqual(offer.signature, Data([1, 2, 3]))
        XCTAssertEqual(offer.expiresAt, now.addingTimeInterval(3_600))
        let identifiers = SubscriptionProduct.allCases.map(SubscriptionRetentionOffer.identifier)
        XCTAssertEqual(Set(identifiers).count, 3)
        XCTAssertTrue(identifiers.contains("granttap_personal_plus_half_month_v1"))
        XCTAssertTrue(identifiers.contains("granttap_fleet_half_month_v1"))
        let invalid: [[String: Any]] = [["productId": "unknown"], ["offerId": "different"],
            ["keyId": ""], ["nonce": "not-a-uuid"], ["signature": "!"],
            ["signature": Data().base64EncodedString()], ["signature": Data(repeating: 0, count: 257).base64EncodedString()],
            ["timestamp": 0], ["timestamp": 1_800_000_061_000], ["expiresAt": Double.infinity],
            ["expiresAt": 1_800_000_000_000.0], ["expiresAt": 1_800_100_000_000.0]]
        for replacement in invalid {
            XCTAssertThrowsError(try SubscriptionRetentionOffer(value.merging(replacement) { _, new in new }, now: now))
        }
        for key in value.keys {
            var incomplete = value
            incomplete.removeValue(forKey: key)
            XCTAssertThrowsError(try SubscriptionRetentionOffer(incomplete, now: now))
        }
    }

    func testOldOrUnavailableStoreOfferCannotStartAPurchase() async throws {
        let store = SubscriptionStore(startObserving: false, betaEnvironmentLoader: { false },
            currentAccountID: { "owner" })
        let offer = try SubscriptionRetentionOffer(value, now: now)
        XCTAssertNil(SubscriptionRetentionPrice(offer: offer, products: [], now: now))
        await store.purchaseRetention(offer)
        XCTAssertNotNil(store.lastError)
        XCTAssertFalse(store.purchaseInProgress)
    }

    func testFeedbackTransportDoesNotAcceptAnAccountSwitch() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RetentionURLProtocol.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel() }
        let session = GrantTapAccountSession(accountId: "owner", token: String(repeating: "A", count: 43))
        let result = try await SubscriptionRetentionAPI.post("cancellation-feedback", body: ["reason": "price"],
            session: session, transport: transport, currentSession: { session })
        XCTAssertEqual(result["saved"] as? Bool, true)
        XCTAssertEqual(RetentionURLProtocol.path, "/api/account/subscriptions/cancellation-feedback")
        XCTAssertEqual(RetentionURLProtocol.method, "POST")
        XCTAssertTrue(RetentionURLProtocol.authorized)
        do {
            _ = try await SubscriptionRetentionAPI.post("cancellation-offer", body: ["intent": "cancel"],
                session: session, transport: transport, currentSession: { nil })
            XCTFail("Changed accounts must not receive an offer")
        } catch { XCTAssertTrue(error is CancellationError) }
        do {
            _ = try await SubscriptionRetentionAPI.post("cancellation-offer", body: [:],
                session: nil, transport: transport, currentSession: { nil })
            XCTFail("A purchase account is required")
        } catch { XCTAssertTrue(error is ManagedSubscriptionError) }
    }

    func testOfferAndFeedbackResponsesUseTheVerifiedAccountSession() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RetentionURLProtocol.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel() }
        let session = GrantTapAccountSession(accountId: "owner", token: String(repeating: "A", count: 43))
        RetentionURLProtocol.payload = try JSONSerialization.data(withJSONObject: ["offer": value])
        let offer = try await SubscriptionRetentionAPI.offer(session: session, transport: transport,
            currentSession: { session }, clock: { self.now })
        XCTAssertEqual(offer?.offerID, "granttap_personal_half_month_v1")
        RetentionURLProtocol.payload = Data(#"{"offer":null}"#.utf8)
        let absent = try await SubscriptionRetentionAPI.offer(session: session, transport: transport,
            currentSession: { session }, clock: { self.now })
        XCTAssertNil(absent)
        RetentionURLProtocol.payload = Data(#"{"offer":"malformed"}"#.utf8)
        do {
            _ = try await SubscriptionRetentionAPI.offer(session: session, transport: transport,
                currentSession: { session }, clock: { self.now })
            XCTFail("Malformed offers must not start a purchase")
        } catch { XCTAssertTrue(error is AccountBridgeError) }
        RetentionURLProtocol.payload = Data(#"{"saved":true}"#.utf8)
        try await SubscriptionRetentionAPI.feedback(id: UUID(), reason: "price", comment: "",
            session: session, transport: transport, currentSession: { session })
        RetentionURLProtocol.payload = Data(#"{"saved":false}"#.utf8)
        do {
            try await SubscriptionRetentionAPI.feedback(id: UUID(), reason: "price", comment: "",
                session: session, transport: transport, currentSession: { session })
            XCTFail("A rejected submission is not a saved response")
        } catch { XCTAssertTrue(error is AccountBridgeError) }
        RetentionURLProtocol.payload = Data(#"{"saved":true}"#.utf8)
    }

    func testTestFlightSupportScreenRendersWithoutRequestingAPurchase() throws {
        let store = SubscriptionStore(startObserving: false, productLoader: { [] },
            betaEnvironmentLoader: { true }, currentAccountID: { "owner" })
        store.betaRelayAccess = true
        let image = DesignSnapshotTests.render(SubscriptionCancellationView(store: store))
        XCTAssertGreaterThan(image.pngData()?.count ?? 0, 8_000)
        XCTAssertTrue(store.hasTestingAccess)
        XCTAssertFalse(store.purchaseInProgress)
        let capture = XCTAttachment(image: image)
        capture.name = "Optional subscription support with free TestFlight access"
        capture.lifetime = .keepAlways
        add(capture)
    }

}

private final class RetentionURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var payload = Data(#"{"saved":true}"#.utf8)
    nonisolated(unsafe) static var path = ""
    nonisolated(unsafe) static var method = ""
    nonisolated(unsafe) static var authorized = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.path = request.url!.path
        Self.method = request.httpMethod ?? ""
        Self.authorized = request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
