import XCTest
import TweetNacl
@testable import GrantTap

final class TaskContinuationEncodingTests: XCTestCase {
    func testEncryptedContinuationForEveryProviderDoesNotCarryAFabricatedNativeID() throws {
        let phone = try NaclBox.keyPair(), machine = try NaclBox.keyPair()
        let pairing = Pairing(relayUrl: "https://continuation.test", room: String(repeating: "a", count: 32),
            role: "phone", deviceName: "Fixture", senderId: "fixture",
            myPublicKey: phone.publicKey.base64EncodedString(), mySecretKey: phone.secretKey.base64EncodedString(),
            peerPublicKey: machine.publicKey.base64EncodedString(), pushAuth: String(repeating: "b", count: 64))
        for agent in ["codex", "claude", "cursor", "grok"] {
            var message = Payloads.message("Synthetic continuation", messageId: "continuation-job", agent: agent,
                cwd: nil, sessionId: nil, requestId: nil)
            message.type = "user.message.continue"
            message.originMessageId = "parent-message"
            let reservation = try RelayTaskQueueEncoding.prepare(message, pairing: pairing,
                notBefore: 1_000_000, now: 1_000_000, sendImmediately: true)
            let envelope = try XCTUnwrap(reservation.envelope)
            let plain = try XCTUnwrap(Crypto.open(nonceB64: envelope.nonce, boxB64: envelope.box,
                theirPublicKeyB64: pairing.myPublicKey, mySecretKeyB64: machine.secretKey.base64EncodedString()))
            let job = try JSONDecoder().decode(RelayQueuedTask.self, from: plain)
            XCTAssertEqual(job.operation.type, "user.message.continue")
            XCTAssertEqual(job.operation.originMessageId, "parent-message")
            XCTAssertEqual(job.operation.agent, agent)
            XCTAssertNil(job.operation.sessionId)
            XCTAssertNil(job.operation.cwd)
            XCTAssertNil(job.sessionId)
            XCTAssertEqual(job.expiresAt, 1_000_000 + 30 * 86_400_000)
            var invalid = message
            invalid.sessionId = "invented-native"
            XCTAssertThrowsError(try RelayTaskQueueEncoding.prepare(invalid, pairing: pairing,
                notBefore: 1_000_000, now: 1_000_000))
            invalid = message
            invalid.taskOriginId = "another-parent"
            XCTAssertThrowsError(try RelayTaskQueueEncoding.prepare(invalid, pairing: pairing,
                notBefore: 1_000_000, now: 1_000_000))
            invalid = message
            invalid.type = "user.message"
            XCTAssertThrowsError(try RelayTaskQueueEncoding.prepare(invalid, pairing: pairing,
                notBefore: 1_000_000, now: 1_000_000))
        }
    }
}
