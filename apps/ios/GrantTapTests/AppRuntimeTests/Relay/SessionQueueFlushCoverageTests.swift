import XCTest
import TweetNacl
@testable import GrantTap

extension AppRuntimeTests {
    func testSessionQueueFlushesCachedKeyAndRequeuesDisconnectedTransport() throws {
        let client = RelayClient(pairing: try transportPairing())
        client.sessionKeys["session-a"] = Data(repeating: 3, count: 32).base64EncodedString()
        let payload = SessionShellSet(
            type: "session.shell.set", sessionId: "session-a",
            allowed: true, createdAt: 1
        )
        client.sendSession(payload: payload, sessionId: "session-a", ttl: 60)

        XCTAssertEqual(client.pendingSessionIds(room: "room-a"), ["session-a"])
        XCTAssertNotNil(client.sessionSubscriptionRetryTokens["session-a"])
        client.resumePendingSessionPayloads()
        XCTAssertEqual(client.pendingSessionIds(room: "room-a"), ["session-a"])
    }

    func testSessionQueueFlushRejectsEntryWhosePayloadScopeChanged() throws {
        let client = RelayClient(pairing: try transportPairing())
        client.sessionKeys["session-a"] = Data(repeating: 4, count: 32).base64EncodedString()
        let wrong = try JSONEncoder().encode(SessionShellSet(
            type: "session.shell.set", sessionId: "different",
            allowed: false, createdAt: 1
        ))
        let queueKey = RelayClient.PendingSessionQueueKey(
            room: "room-a", sessionId: "session-a", payload: .shell
        )
        var result: Error?
        let entry = RelayClient.PendingSessionPayload(
            id: UUID(), queueKey: queueKey, plain: wrong,
            expiresAt: Date().timeIntervalSince1970 + 60, deliveryId: "wrong",
            completion: { result = $0 }
        )
        client.pendingSessionPayloads[queueKey] = entry
        client.latestSessionPayloadIds[queueKey] = entry.id

        client.flushPendingSessionPayloads(sessionId: "session-a", room: "room-a")

        XCTAssertTrue(result is RelaySendError)
        XCTAssertTrue(client.pendingSessionPayloads.isEmpty)
        client.flushPendingSessionPayloads(sessionId: "", room: "room-a")
    }

    private func transportPairing() throws -> Pairing {
        let phone = try NaclBox.keyPair()
        let machine = try NaclBox.keyPair()
        return Pairing(
            relayUrl: "wss://relay.granttap.app", room: "room-a", role: "phone",
            deviceName: "Phone", senderId: "phone",
            myPublicKey: phone.publicKey.base64EncodedString(),
            mySecretKey: phone.secretKey.base64EncodedString(),
            peerPublicKey: machine.publicKey.base64EncodedString()
        )
    }
}
