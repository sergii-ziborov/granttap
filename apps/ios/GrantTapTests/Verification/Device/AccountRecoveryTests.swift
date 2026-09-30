import TweetNacl
import XCTest
@testable import GrantTap

final class AccountRecoveryTests: XCTestCase {
    func testEncryptedOfferOpensOnlyForMatchingRequestAndComputer() throws {
        let sender = try NaclBox.keyPair()
        let receiver = try NaclBox.keyPair()
        let requestId = UUID().uuidString.lowercased()
        let machineId = UUID().uuidString.lowercased()
        let pairing = Pairing(
            relayUrl: "wss://relay.granttap.com", room: String(repeating: "a", count: 32),
            role: "phone", deviceName: "Mac", senderId: "phone",
            myPublicKey: receiver.publicKey.base64EncodedString(),
            mySecretKey: receiver.secretKey.base64EncodedString(),
            peerPublicKey: sender.publicKey.base64EncodedString())
        let body = try JSONEncoder().encode(Offer(schema: "granttap.account-offer.v1",
                                                  requestId: requestId, machineId: machineId,
                                                  pairing: pairing))
        let sealed = try Crypto.seal(body,
                                     theirPublicKeyB64: receiver.publicKey.base64EncodedString(),
                                     mySecretKeyB64: sender.secretKey.base64EncodedString())
        let envelope = try JSONEncoder().encode(Envelope(
            senderPublicKey: sender.publicKey.base64EncodedString(),
            nonce: sealed.nonce, box: sealed.box))
        let text = try XCTUnwrap(String(data: envelope, encoding: .utf8))
        XCTAssertEqual(try AccountRecovery.open(text, requestId: requestId,
                                                machineId: machineId,
                                                secretKey: receiver.secretKey), pairing)
        XCTAssertThrowsError(try AccountRecovery.open(text, requestId: UUID().uuidString,
                                                      machineId: machineId,
                                                      secretKey: receiver.secretKey))
        XCTAssertThrowsError(try AccountRecovery.open(text, requestId: requestId,
                                                      machineId: UUID().uuidString,
                                                      secretKey: receiver.secretKey))
        XCTAssertThrowsError(try AccountRecovery.open(text, requestId: requestId,
                                                      machineId: machineId,
                                                      secretKey: sender.secretKey))
    }

    func testAccountBase64URLRejectsMalformedInput() {
        let data = Data(repeating: 0xfb, count: 32)
        XCTAssertEqual(GrantTapAccountAPI.decodeURL(GrantTapAccountAPI.encodeURL(data)), data)
        XCTAssertNil(GrantTapAccountAPI.decodeURL("not valid"))
    }

    func testAccountResponsesValidateSessionAndComputerList() async throws {
        let transport = stubTransport()
        let session = GrantTapAccountSession(accountId: UUID().uuidString,
                                             token: String(repeating: "t", count: 43))
        defer { StubURLProtocol.handler = nil; transport.invalidateAndCancel() }
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/account/machines")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"),
                           "Bearer \(session.token)")
            return (200, try JSONSerialization.data(withJSONObject: ["machines": [
                ["id": UUID().uuidString, "name": "Mac.lan", "createdAt": 1.0],
            ]]))
        }
        let computers = try await AccountRecovery.computers(session: session, transport: transport)
        XCTAssertEqual(computers.map(\.name), ["Mac.lan"])

        StubURLProtocol.handler = { _ in (401, Data("{}".utf8)) }
        do {
            _ = try await AccountRecovery.computers(session: session, transport: transport)
            XCTFail("An expired account session must be rejected")
        } catch AccountBridgeError.expired { }

        StubURLProtocol.handler = { _ in (200, Data("{\"machines\":true}".utf8)) }
        do {
            _ = try await AccountRecovery.computers(session: session, transport: transport)
            XCTFail("Malformed computer lists must be rejected")
        } catch AccountBridgeError.invalidResponse { }
    }

    func testPasskeyOptionsRejectMalformedChallengesBeforeAuthorization() async throws {
        let transport = stubTransport()
        defer { StubURLProtocol.handler = nil; transport.invalidateAndCancel() }
        StubURLProtocol.handler = { _ in (200, Data("{\"ceremonyId\":\"id\",\"options\":{\"challenge\":\"bad\"}}".utf8)) }
        do {
            _ = try await GrantTapAccountAPI.authenticate(register: false, transport: transport)
            XCTFail("Short challenges must be rejected before invoking AuthenticationServices")
        } catch AccountBridgeError.invalidResponse { }

        let challenge = GrantTapAccountAPI.encodeURL(Data(repeating: 7, count: 32))
        StubURLProtocol.handler = { _ in (200, try JSONSerialization.data(withJSONObject: [
            "ceremonyId": "id", "options": ["challenge": challenge],
        ])) }
        do {
            _ = try await GrantTapAccountAPI.authenticate(register: true, transport: transport)
            XCTFail("Registration requires the service's user identity")
        } catch AccountBridgeError.invalidResponse { }
        for error in [AccountBridgeError.invalidResponse, .unavailable, .expired, .storage] {
            XCTAssertFalse(try XCTUnwrap(error.errorDescription).isEmpty)
        }
    }

    func testAccountServiceRecoversFreshEncryptedPhonePairing() async throws {
        let transport = stubTransport()
        defer { StubURLProtocol.handler = nil; transport.invalidateAndCancel() }
        let sender = try NaclBox.keyPair()
        let session = GrantTapAccountSession(accountId: UUID().uuidString,
                                             token: String(repeating: "t", count: 43))
        let computer = AccountComputer(id: UUID().uuidString.lowercased(), name: "Mac.lan",
                                       createdAt: 1, lastSeenAt: nil)
        let requestId = UUID().uuidString.lowercased()
        var sealedOffer = ""
        var polls = 0
        StubURLProtocol.handler = { request in
            if request.httpMethod == "POST" {
                XCTAssertEqual(request.url?.path,
                               "/api/account/machines/\(computer.id)/requests")
                let body = try XCTUnwrap(Self.requestBody(request))
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
                let publicKey = try XCTUnwrap(GrantTapAccountAPI.decodeURL(object["phonePublicKey"]))
                let receiver = try NaclBox.keyPair()
                let pairing = Pairing(relayUrl: "wss://relay.granttap.com",
                                      room: String(repeating: "a", count: 32), role: "phone",
                                      deviceName: "Mac", senderId: "phone",
                                      myPublicKey: receiver.publicKey.base64EncodedString(),
                                      mySecretKey: receiver.secretKey.base64EncodedString(),
                                      peerPublicKey: sender.publicKey.base64EncodedString())
                let offer = try JSONEncoder().encode(Offer(schema: "granttap.account-offer.v1",
                                                           requestId: requestId,
                                                           machineId: computer.id, pairing: pairing))
                let box = try Crypto.seal(offer, theirPublicKeyB64: publicKey.base64EncodedString(),
                                          mySecretKeyB64: sender.secretKey.base64EncodedString())
                sealedOffer = try String(data: JSONEncoder().encode(Envelope(
                    senderPublicKey: sender.publicKey.base64EncodedString(),
                    nonce: box.nonce, box: box.box)), encoding: .utf8) ?? ""
                return (200, try JSONSerialization.data(withJSONObject: ["id": requestId]))
            }
            XCTAssertEqual(request.url?.path, "/api/account/requests/\(requestId)")
            polls += 1
            let result: [String: String] = polls == 1 ? ["status": "pending"]
                : ["status": "ready", "encryptedOffer": sealedOffer]
            return (200, try JSONSerialization.data(withJSONObject: result))
        }
        let pairing = try await AccountRecovery.connect(computer, session: session,
                                                         transport: transport, pollDelayNanoseconds: 0)
        XCTAssertEqual(pairing.deviceName, "Mac")
        XCTAssertEqual(polls, 2)
    }

    private func stubTransport() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func requestBody(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var body = Data()
        var bytes = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            guard count > 0 else { break }
            body.append(contentsOf: bytes[..<count])
        }
        return body
    }

    private final class StubURLProtocol: URLProtocol {
        static var handler: ((URLRequest) throws -> (Int, Data))?
        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.host == "granttap.com"
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            do {
                let (status, data) = try Self.handler!(request)
                let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                               httpVersion: "HTTP/1.1", headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
        override func stopLoading() { }
    }

    private struct Envelope: Encodable {
        let senderPublicKey: String
        let nonce: String
        let box: String
    }

    private struct Offer: Encodable {
        let schema: String
        let requestId: String
        let machineId: String
        let pairing: Pairing
    }
}
