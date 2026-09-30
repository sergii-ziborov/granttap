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
