import XCTest
@testable import GrantTap

@MainActor
final class RelayConnectionStatusTests: XCTestCase {
    func testRelayIsLiveWithoutAComputerHeartbeatOrCatalog() {
        let model = AppModel()
        let pair = Pairing(relayUrl: "wss://relay.test", room: "fixture-relay", role: "phone",
            deviceName: "Workstation", senderId: "fixture", myPublicKey: "", mySecretKey: "", peerPublicKey: "")
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: pair, prefer: true)
        model.roomRuntime[pair.room] = .init(socketUp: true, socketUpSince: Date().timeIntervalSince1970 * 1000)
        XCTAssertEqual(model.relayConnectionSnapshot.phase, .live)
        XCTAssertNotEqual(model.connectionSnapshot.phase, .live, "Computer freshness remains independent")
        model.roomRuntime[pair.room]?.socketUp = false
        XCTAssertEqual(model.relayConnectionSnapshot.phase, .phoneOffline)
    }

    func testPresenceIsScopedAndCannotMasqueradeAsAgentActivity() throws {
        let now = Date().timeIntervalSince1970 * 1000
        let value: [String: Any] = ["type": "relay.presence", "room": "fixture", "generatedAt": now,
            "devices": [["id": String(repeating: "a", count: 64), "role": "machine", "online": false, "lastSeenAt": now - 1000]]]
        let data = try JSONSerialization.data(withJSONObject: value)
        XCTAssertNotNil(RelayPresence.decode(data, room: "fixture", now: now))
        XCTAssertNil(RelayPresence.decode(data, room: "other", now: now))
        XCTAssertNil(RelayPresence.decode(data, room: "fixture", now: now - 60000))
    }
}
