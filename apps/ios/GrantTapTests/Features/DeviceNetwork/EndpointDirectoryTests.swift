import TweetNacl
import XCTest
@testable import GrantTap

final class EndpointDirectoryTests: XCTestCase {
    func testUnsubscribedPhoneResolvesAuthenticatedMacWithoutSendingKeys() async throws {
        let (pairing, secret) = try identity()
        let now = Date(timeIntervalSince1970: 1_000)
        let record = try announcement(pairing, secret: secret, expiresAt: 1_600_000)
        var queried: URLRequest?
        let resolved = await DeviceEndpointDirectory.resolve(pairing: pairing, allowsManaged: false,
            now: now, loader: { request in
                queried = request
                return (record, HTTPURLResponse(url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: nil)!)
            })
        XCTAssertEqual(resolved, "wss://mac.example:8443")
        XCTAssertEqual(queried?.url?.host, "relay.granttap.com")
        XCTAssertEqual(queried?.url?.path, "/endpoint")
        XCTAssertFalse(queried!.url!.absoluteString.contains(pairing.mySecretKey))
        XCTAssertEqual(URLComponents(url: queried!.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "recipient" }?.value?.count, 64)
    }

    func testExpiredTamperedWrongRoomOrBadEndpointDoesNotFallBackToPaidTransport() async throws {
        let (pairing, secret) = try identity()
        let now = Date(timeIntervalSince1970: 1_000)
        for record in [
            try announcement(pairing, secret: secret, expiresAt: 999_000),
            try announcement(pairing, secret: secret, expiresAt: 1_600_000, room: "wrong"),
            try announcement(pairing, secret: secret, expiresAt: 1_600_000, endpoint: "ws://public.example"),
            Data("{\"nonce\":\"bad\",\"box\":\"bad\",\"expiresAt\":1600000}".utf8),
        ] {
            let result = await DeviceEndpointDirectory.resolve(pairing: pairing,
                allowsManaged: false, now: now, loader: { request in
                    (record, HTTPURLResponse(url: request.url!, statusCode: 200,
                                            httpVersion: nil, headerFields: nil)!)
                })
            XCTAssertNil(result)
        }
    }

    func testHostedAccessAndSelfHostingAreIndependent() async throws {
        var (pairing, _) = try identity()
        let unavailable: DeviceEndpointDirectory.Loader = { _ in throw URLError(.notConnectedToInternet) }
        let paid = await DeviceEndpointDirectory.resolve(pairing: pairing, allowsManaged: true, loader: unavailable)
        XCTAssertEqual(paid, pairing.relayUrl)
        let unpaid = await DeviceEndpointDirectory.resolve(pairing: pairing, allowsManaged: false, loader: unavailable)
        XCTAssertNil(unpaid)
        pairing.relayUrl = "wss://own.example"
        let own = await DeviceEndpointDirectory.resolve(pairing: pairing, allowsManaged: false, loader: unavailable)
        XCTAssertEqual(own, pairing.relayUrl)
    }

    private func identity() throws -> (Pairing, String) {
        let phone = try NaclBox.keyPair(), mac = try NaclBox.keyPair()
        return (Pairing(relayUrl: Pairing.currentRelaySocket, room: String(repeating: "a", count: 32),
            role: "phone", deviceName: "test", senderId: "phone",
            myPublicKey: phone.publicKey.base64EncodedString(), mySecretKey: phone.secretKey.base64EncodedString(),
            peerPublicKey: mac.publicKey.base64EncodedString(), pushAuth: String(repeating: "b", count: 64)),
            mac.secretKey.base64EncodedString())
    }

    private func announcement(_ pairing: Pairing, secret: String, expiresAt: Double,
                              room: String? = nil, endpoint: String = "wss://mac.example:8443") throws -> Data {
        let payload: [String: Any] = ["schema": "granttap.direct-endpoint.v1",
            "room": room ?? pairing.room, "relayUrl": endpoint, "expiresAt": expiresAt]
        let sealed = try Crypto.seal(JSONSerialization.data(withJSONObject: payload),
                                    theirPublicKeyB64: pairing.myPublicKey, mySecretKeyB64: secret)
        return try JSONSerialization.data(withJSONObject: ["nonce": sealed.nonce, "box": sealed.box,
                                                           "expiresAt": expiresAt])
    }
}
