import XCTest
@testable import GrantTap

/// A relay that refuses a connection right after it opens must not be asked
/// again every second forever; a healthy connection that drops reconnects fast.
final class RelayReconnectBackoffTests: XCTestCase {
    func testAShortLivedConnectionKeepsBackingOff() {
        XCTAssertEqual(RelayReconnectBackoff.delayAfterClose(current: 8, openFor: 0.15, closeCode: 1000), 8,
                       "a connection that opened and dropped at once does not reset the backoff")
        XCTAssertEqual(RelayReconnectBackoff.delayAfterClose(current: 8, openFor: nil, closeCode: 1006), 8)
    }

    func testAHealthyConnectionReconnectsQuicklyAfterItDrops() {
        XCTAssertEqual(RelayReconnectBackoff.delayAfterClose(current: 15, openFor: 45, closeCode: 1006), 1)
    }

    func testAPolicyRefusalWaitsAtLeastAMinute() {
        XCTAssertEqual(RelayReconnectBackoff.delayAfterClose(current: 1, openFor: 0.15, closeCode: 1008), 60)
        XCTAssertEqual(RelayReconnectBackoff.delayAfterClose(current: 1, openFor: 120, closeCode: 1008), 60,
                       "a refusal is a refusal even after a long session")
        XCTAssertEqual(RelayReconnectBackoff.nextDelay(after: 60, cap: 15), 60,
                       "the ordinary cap does not shorten a policy wait")
        XCTAssertEqual(RelayReconnectBackoff.nextDelay(after: 4, cap: 15), 8)
        XCTAssertEqual(RelayReconnectBackoff.nextDelay(after: 8, cap: 15), 15)
    }

    @MainActor
    func testAClientThatWasRefusedDoesNotResetItsBackoffWhenTheNextSocketOpens() {
        let client = RelayClient(pairing: Pairing(relayUrl: "ws://127.0.0.1:1", room: "room-a", role: "machine",
            deviceName: "Hub", senderId: "hub-test", myPublicKey: "test-public", mySecretKey: "test-secret",
            peerPublicKey: "test-peer"))
        client.retryDelay = 60
        client.noteSocketOpened(now: 100)
        XCTAssertEqual(client.retryDelay, 60)
        client.noteSocketClosed(closeCode: 1008, now: 100.2)
        XCTAssertEqual(client.retryDelay, 60)
        client.noteSocketOpened(now: 200)
        client.noteSocketClosed(closeCode: 1006, now: 260)
        XCTAssertEqual(client.retryDelay, 1)
    }
}
