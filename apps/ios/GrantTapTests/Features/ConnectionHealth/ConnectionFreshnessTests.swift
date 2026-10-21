import XCTest
@testable import GrantTap

final class ConnectionFreshnessTests: XCTestCase {
    @MainActor
    func testInitialHandshakeShowsConnectingUntilAuthenticatedComputerResponds() {
        let model = AppModel()
        let pairing = Pairing(relayUrl: "ws://127.0.0.1:1", room: "startup-test",
            role: "phone", deviceName: "Workstation", senderId: "test",
            myPublicKey: "public", mySecretKey: "secret", peerPublicKey: "peer")
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: pairing, prefer: true)
        model.attachRelay(for: pairing)
        defer { model.relaysByRoom[pairing.room]?.disconnect() }
        XCTAssertEqual(model.connectionSnapshot.statusTitle, L("Connecting…"))
        XCTAssertFalse(ConnectionSnapshot.needsAttention(model.connectionSnapshot.phase))
        model.roomRuntime[pairing.room]?.socketUp = true
        model.roomRuntime[pairing.room]?.lastHeartbeatAt = Date().timeIntervalSince1970 * 1_000
        XCTAssertEqual(model.connectionSnapshot.phase, .live)
    }

    @MainActor
    func testBeginningAConnectionCheckInvalidatesAnAlreadyVisibleHeader() {
        let model = AppModel()
        var changes = 0
        let observation = model.objectWillChange.sink { changes += 1 }
        model.beginConnectionCheck(room: "visible-room")
        XCTAssertGreaterThan(changes, 0)
        XCTAssertGreaterThan(model.roomRuntime["visible-room"]?.connectingSince ?? 0, 0)
        withExtendedLifetime(observation) {}
    }

    func testConnectionCheckExpiresAndDoesNotReplaceAuthenticatedLiveState() {
        let start = 1_000_000.0
        for socketUp in [false, true] {
            XCTAssertEqual(ConnectionFreshness.phase(socketUp: socketUp, disconnectedAt: 0,
                heartbeatAt: 0, catalogAt: 0, socketUpSince: start, now: start + 5_000,
                connectingSince: start), .connecting)
            XCTAssertEqual(ConnectionFreshness.phase(socketUp: socketUp, disconnectedAt: 0,
                heartbeatAt: 0, catalogAt: 0, socketUpSince: start, now: start + 15_000,
                connectingSince: start), socketUp ? .macOffline : .phoneOffline)
        }
        XCTAssertEqual(ConnectionFreshness.phase(socketUp: true, disconnectedAt: 0,
            heartbeatAt: start + 500, catalogAt: 0, socketUpSince: start, now: start + 1_000,
            connectingSince: start), .live)
    }

    func testPoweredOffComputerDoesNotBlinkOfflineDuringRelayReconnect() {
        let now: Double = 1_000_000
        for delta in [0.0, 500, 1_500] {
            XCTAssertEqual(ConnectionFreshness.phase(socketUp: false, disconnectedAt: now,
                heartbeatAt: now - 120_000, catalogAt: now - 150_000,
                socketUpSince: now - 60_000, now: now + delta), .macOffline)
        }
        XCTAssertEqual(ConnectionFreshness.phase(socketUp: false, disconnectedAt: now,
            heartbeatAt: now - 120_000, catalogAt: now - 150_000,
            socketUpSince: now - 60_000, now: now + 2_000), .phoneOffline)
    }

    func testOnlyBriefTransportLossKeepsFreshComputerVisibleAsLive() {
        let now: Double = 1_000_000
        XCTAssertEqual(ConnectionFreshness.phase(socketUp: false, disconnectedAt: now - 500,
            heartbeatAt: now - 10_000, catalogAt: 0, socketUpSince: 0, now: now), .live)
        XCTAssertEqual(ConnectionFreshness.phase(socketUp: false, disconnectedAt: now - 2_000,
            heartbeatAt: now - 10_000, catalogAt: 0, socketUpSince: 0, now: now), .phoneOffline)
        XCTAssertEqual(ConnectionFreshness.phase(socketUp: false, disconnectedAt: now - 500,
            heartbeatAt: now - 100_000, catalogAt: 0, socketUpSince: 0, now: now), .phoneOffline)
        XCTAssertEqual(ConnectionFreshness.phase(socketUp: true, disconnectedAt: 0,
            heartbeatAt: now - 10_000, catalogAt: 0, socketUpSince: now, now: now), .live)
        XCTAssertEqual(ConnectionFreshness.phase(socketUp: true, disconnectedAt: 0,
            heartbeatAt: 0, catalogAt: now - 10_000, socketUpSince: now, now: now), .live)
        XCTAssertEqual(ConnectionFreshness.phase(socketUp: true, disconnectedAt: 0,
            heartbeatAt: 0, catalogAt: now + 40_000, socketUpSince: now, now: now), .macOffline)
        XCTAssertEqual(ConnectionFreshness.phase(socketUp: true, disconnectedAt: 0,
            heartbeatAt: 0, catalogAt: 0, socketUpSince: now - 200_000, now: now), .needRepair)
        XCTAssertEqual(ConnectionFreshness.phase(socketUp: false, disconnectedAt: 0,
            heartbeatAt: now, catalogAt: 0, socketUpSince: 0, now: now), .phoneOffline)
    }
}
