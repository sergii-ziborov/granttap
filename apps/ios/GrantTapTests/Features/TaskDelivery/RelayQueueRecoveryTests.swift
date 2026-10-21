import XCTest
import TweetNacl
@testable import GrantTap

final class RelayQueueRecoveryTests: XCTestCase {
    func testAStaleListCannotMoveAcceptedWorkBackIntoTheWaitingQueue() {
        XCTAssertFalse(RelayTaskJobState.accepted.canAdvance(to: .queued))
        XCTAssertTrue(RelayTaskJobState.accepted.canAdvance(to: .completed))
        XCTAssertFalse(RelayTaskJobState.completed.canAdvance(to: .failed))
        XCTAssertTrue(RelayTaskJobState.failed.canAdvance(to: .cancelled))
    }

    func testRelayCiphertextReconstructsTheQueueWithoutTheComputerOrLocalOutbox() throws {
        let phone = try NaclBox.keyPair(), machine = try NaclBox.keyPair()
        let pair = Pairing(relayUrl: "wss://relay.test", room: String(repeating: "a", count: 32),
            role: "phone", deviceName: "Fixture", senderId: "fixture", myPublicKey: phone.publicKey.base64EncodedString(),
            mySecretKey: phone.secretKey.base64EncodedString(), peerPublicKey: machine.publicKey.base64EncodedString())
        let message = Payloads.message("Synthetic recovery", messageId: "recovery-fixture-01", agent: "codex",
            cwd: nil, sessionId: "fixture-chat", requestId: nil,
            attachments: [UserAttachment(name: "fixture.png", mimeType: "image/png", data: "AQID")], model: "fixture-model")
        let reservation = try RelayTaskQueueEncoding.prepare(message, pairing: pair, notBefore: 1000100,
            now: 1000000, sendImmediately: true)
        let stored = RelayTaskQueueRecovery.StoredJob(id: reservation.jobId, state: .queued,
            notBefore: reservation.notBefore, expiresAt: reservation.expiresAt, envelope: try XCTUnwrap(reservation.envelope))
        let row = try XCTUnwrap(RelayTaskQueueRecovery.restore(stored, pairing: pair))
        XCTAssertEqual(row.id, message.messageId)
        XCTAssertEqual(row.text, message.text)
        XCTAssertEqual(row.model, "fixture-model")
        XCTAssertEqual(row.attachments.first?.data, "AQID")
        XCTAssertEqual(row.chatQueue?.sendImmediately, true)
        XCTAssertEqual(row.relayJob?.serverState, .queued)
        var other = pair
        other.room = "other-room"
        XCTAssertNil(RelayTaskQueueRecovery.restore(stored, pairing: other))
        let tampered = RelayTaskQueueRecovery.StoredJob(id: stored.id, state: .queued,
            notBefore: stored.notBefore + 1000, expiresAt: stored.expiresAt, envelope: stored.envelope)
        XCTAssertNil(RelayTaskQueueRecovery.restore(tampered, pairing: pair))
    }
}
