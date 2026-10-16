import XCTest
import CryptoKit
import TweetNacl
@testable import GrantTap

@MainActor
final class CiphertextRecipientTests: XCTestCase {
    func testAddressedCiphertextIsCheckedBeforeDispatchAndLegacyPacketsRemainReadable() throws {
        let phone = try NaclBox.keyPair(), machine = try NaclBox.keyPair()
        let pairing = Pairing(relayUrl: Pairing.currentRelaySocket, room: String(repeating: "a", count: 32),
            role: "phone", deviceName: "Fixture", senderId: "fixture",
            myPublicKey: phone.publicKey.base64EncodedString(), mySecretKey: phone.secretKey.base64EncodedString(),
            peerPublicKey: machine.publicKey.base64EncodedString())
        let client = RelayClient(pairing: pairing)
        var received = 0
        client.onMachineHeartbeat = { _ in received += 1 }
        let sealed = try Crypto.seal(JSONSerialization.data(withJSONObject: [
            "type": "machine.heartbeat", "machine": "Fixture", "createdAt": 1]),
            theirPublicKeyB64: pairing.myPublicKey, mySecretKeyB64: machine.secretKey.base64EncodedString())
        var envelope: [String: Any] = ["v": 1, "room": pairing.room, "from": "machine",
            "to": "phone", "senderId": "fixture", "nonce": sealed.nonce, "box": sealed.box,
            "recipientKeyId": String(repeating: "0", count: 64)]
        func deliver() throws {
            client.handle(String(decoding: try JSONSerialization.data(withJSONObject: envelope), as: UTF8.self))
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        }
        try deliver()
        XCTAssertEqual(received, 0, "Another recipient's packet must not dispatch or consume this ciphertext")
        envelope["recipientKeyId"] = SHA256.hash(data: phone.publicKey).map { String(format: "%02x", $0) }.joined()
        try deliver()
        XCTAssertEqual(received, 1)
        let legacy = RelayClient(pairing: pairing)
        legacy.onMachineHeartbeat = { _ in received += 1 }
        envelope.removeValue(forKey: "recipientKeyId")
        legacy.handle(String(decoding: try JSONSerialization.data(withJSONObject: envelope), as: UTF8.self))
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        XCTAssertEqual(received, 2, "Earlier encrypted envelopes stay compatible")
    }
}
