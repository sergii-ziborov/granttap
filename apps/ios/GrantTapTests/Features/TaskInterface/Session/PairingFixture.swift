@testable import GrantTap

/// A pairing that never connects, for tests that only need a room to exist.
enum PairingFixture {
    static func pairing(room: String, deviceName: String = "Test Mac") -> Pairing {
        Pairing(
            relayUrl: "ws://127.0.0.1:1", room: room, role: "phone", deviceName: deviceName,
            senderId: "test-sender", myPublicKey: "test-public", mySecretKey: "test-secret",
            peerPublicKey: "test-peer"
        )
    }
}
