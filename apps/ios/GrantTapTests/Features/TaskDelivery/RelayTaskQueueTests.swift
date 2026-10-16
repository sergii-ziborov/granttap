import XCTest
import TweetNacl
@testable import GrantTap

final class RelayTaskQueueTests: XCTestCase {
    func testImmutableReservationContainsSignedScheduleAndCompleteInlinePhoto() throws {
        let phone = try NaclBox.keyPair(), machine = try NaclBox.keyPair()
        let pairing = Pairing(relayUrl: "wss://relay.test", room: String(repeating: "a", count: 32),
            role: "phone", deviceName: "Fixture", senderId: "fixture",
            myPublicKey: phone.publicKey.base64EncodedString(), mySecretKey: phone.secretKey.base64EncodedString(),
            peerPublicKey: machine.publicKey.base64EncodedString(), pushAuth: String(repeating: "b", count: 64))
        let image = UserAttachment(name: "photo.png", mimeType: "image/png", data: Data([1, 2, 3]).base64EncodedString())
        let message = Payloads.message("Synthetic queued task", messageId: "queue-fixture-01", agent: "codex", cwd: nil,
                                       sessionId: "fixture-chat", requestId: nil, attachments: [image])
        let reservation = try RelayTaskQueueEncoding.prepare(message, pairing: pairing, notBefore: 1_000_100, now: 1_000_000)
        let body = try reservation.uploadBody()
        XCTAssertEqual(try reservation.uploadBody(), body, "Retries must preserve the same encrypted envelope.")
        let envelope = try XCTUnwrap(reservation.envelope)
        let plain = try XCTUnwrap(Crypto.open(nonceB64: envelope.nonce, boxB64: envelope.box,
            theirPublicKeyB64: pairing.myPublicKey, mySecretKeyB64: machine.secretKey.base64EncodedString()))
        let job = try JSONDecoder().decode(RelayQueuedTask.self, from: plain)
        XCTAssertEqual(job.notBefore, 1_000_100)
        XCTAssertEqual(job.operation.attachments?.first?.data, image.data)
        XCTAssertEqual(job.operation.sessionId, job.sessionId)
        XCTAssertEqual(job.token.count, 64)
        XCTAssertEqual(envelope.deliveryId, message.messageId)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let metadata = try RelayTaskQueueCipherStore.save(reservation, directory: directory)
        XCTAssertNil(metadata.envelope)
        XCTAssertEqual(try RelayTaskQueueCipherStore.restore(metadata, directory: directory).uploadBody(), body)
        RelayTaskQueueCipherStore.remove(reservation.jobId, directory: directory)
        XCTAssertThrowsError(try RelayTaskQueueCipherStore.restore(metadata, directory: directory))
    }

    func testApprovalRepliesAndOutOfBoundsSchedulesCannotBecomeDelayedTaskCommands() throws {
        let pairing = Pairing(relayUrl: "wss://relay.test", room: "fixture", role: "phone", deviceName: "Fixture",
            senderId: "fixture", myPublicKey: "", mySecretKey: "", peerPublicKey: "")
        let approval = Payloads.message("Allow", messageId: "approval-01", agent: nil, cwd: nil, sessionId: "fixture", requestId: "request-01")
        XCTAssertThrowsError(try RelayTaskQueueEncoding.prepare(approval, pairing: pairing, notBefore: 1000, now: 1000))
        let message = Payloads.message("Synthetic", messageId: "queue-fixture-02", agent: nil, cwd: nil, sessionId: "fixture", requestId: nil)
        XCTAssertThrowsError(try RelayTaskQueueEncoding.prepare(message, pairing: pairing, notBefore: 31 * 86_400_000, now: 1000))
    }
}
