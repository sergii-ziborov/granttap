import XCTest
@testable import GrantTap

@MainActor
final class ComposerTurnDeliveryTests: XCTestCase {
    func testHomeComposerSendsPersistedModelAndEffortForNewAndExistingChats() throws {
        let suite = "GrantTap.composer-turn.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel()
        model.deliveries = []
        model.turnOverrides = TurnOverrideStore(defaults: defaults)
        model.turnOverrides.setAgentDefaults(TurnOverrides(model: .sonnet, effort: .high), for: "claude")
        let room = "composer-turn-test"
        let pairing = Pairing(relayUrl: "ws://127.0.0.1:1", room: room, role: "phone",
            deviceName: "Test Mac", senderId: "fixture", myPublicKey: "fixture-public",
            mySecretKey: "fixture-secret", peerPublicKey: "fixture-peer")
        let now = Date().timeIntervalSince1970 * 1_000
        model.connectionRegistry = ConnectionRegistryLogic.noteCatalog(
            ConnectionRegistryLogic.upsert(.empty, pairing: pairing), roomId: room,
            generatedAt: now, machineName: "Test Mac")
        model.roomRuntime[room] = AppModel.RoomRuntime(socketUp: true, socketUpSince: now)
        ContentView(messageText: "Synthetic new task", composeAgent: "claude",
            composeRoomId: room, modelOverride: model).send()
        XCTAssertEqual(model.deliveries.first?.text, "Synthetic new task")
        XCTAssertEqual(model.deliveries.first?.model, "sonnet")
        XCTAssertEqual(model.deliveries.first?.effort, "high")
        model.deliveries = []
        let session = SessionInfo(sessionId: "composer-existing", agent: "claude", title: "Fixture",
            cwd: "/fixture", state: "idle", startedAt: now, lastActivityAt: now,
            tokensSession: 0, tokensLastTurn: 0)
        model.sessions = [session]
        model.rememberSessionSourceRoom(room, sessionId: session.sessionId)
        model.turnOverrides.setChatOverrides(TurnOverrides(model: .haiku, effort: .low), for: session.sessionId)
        ContentView(composeSessionId: session.sessionId, messageText: "Synthetic continuation",
            modelOverride: model).send()
        XCTAssertEqual(model.deliveries.first?.model, "haiku")
        XCTAssertEqual(model.deliveries.first?.effort, "low")
    }
}
