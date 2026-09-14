import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testChatRouteRejectsAmbiguousAndRemovedOwners() {
        let model = AppModel()
        var registry = ConnectionRegistryLogic.upsert(
            .empty, pairing: testPairing(room: "room-a"), prefer: true
        )
        registry = ConnectionRegistryLogic.upsert(
            registry, pairing: testPairing(room: "room-b"), prefer: false
        )
        model.connectionRegistry = registry
        model.rememberSessionSourceRoom("room-a", sessionId: "ambiguous")
        model.rememberSessionSourceRoom("room-b", sessionId: "ambiguous")
        XCTAssertNil(model.chatComputerRoute(forSessionId: "ambiguous"))

        model.sessionSourceRooms["removed"] = ["ghost-room"]
        XCTAssertNil(model.chatComputerRoute(forSessionId: "removed"))
        XCTAssertNil(model.chatComputerRoute(forRoomId: " "))
        XCTAssertNil(model.chatComputerRoute(forRoomId: "ghost-room"))
    }

    @MainActor
    func testStalePreferredCatalogPurgesRemoteGhostsButKeepsLocalTask() {
        let model = AppModel()
        let now = Date().timeIntervalSince1970 * 1_000
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            .empty, pairing: testPairing(room: "room-a"), prefer: true, now: now - 200_000
        )
        model.roomRuntime["room-a"] = AppModel.RoomRuntime(
            socketUp: true, socketUpSince: now - 200_000
        )
        let local = catalogEdgeSession("local", at: now)
        let remote = catalogEdgeSession("remote", at: now)
        model.localOnlySessionIds = [local.sessionId]
        model.sessions = [local, remote]
        model.sessionHistory = [catalogEdgeSession("history", at: now - 1)]

        model.purgeStalePreferredCatalogIfNeeded()

        XCTAssertEqual(model.connectionSnapshot.phase, .needRepair)
        XCTAssertEqual(model.sessions.map(\.sessionId), ["local"])
        XCTAssertTrue(model.sessionHistory.isEmpty)
        XCTAssertTrue(model.log.first?.contains("catalog-isolation") == true)
    }

    @MainActor
    func testRequestRelayMigrationAndRoomCleanupStayExact() {
        let defaults = UserDefaults.standard.object(forKey: "granttap.request-source-rooms")
        defer {
            if let defaults {
                UserDefaults.standard.set(defaults, forKey: "granttap.request-source-rooms")
            } else {
                UserDefaults.standard.removeObject(forKey: "granttap.request-source-rooms")
            }
        }
        let model = AppModel()
        model.requestSourceRoom = [:]
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            .empty, pairing: testPairing(room: "room-a"), prefer: true
        )
        let relay = RelayClient(pairing: testPairing(room: "room-a"))
        model.relaysByRoom["room-a"] = relay
        XCTAssertTrue(model.relayForRequest("legacy") === relay)
        XCTAssertEqual(model.requestSourceRoom["legacy"], "room-a")
        model.requestSourceRoom["other"] = "room-b"
        model.clearRequestRooms(for: "room-a")
        XCTAssertNil(model.requestSourceRoom["legacy"])
        XCTAssertEqual(model.requestSourceRoom["other"], "room-b")

        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            model.connectionRegistry, pairing: testPairing(room: "room-b"), prefer: false
        )
        XCTAssertNil(model.relayForRequest("ambiguous-legacy"))
    }

    private func catalogEdgeSession(_ id: String, at: Double) -> SessionInfo {
        SessionInfo(
            sessionId: id, agent: "codex", title: "Task \(id)", cwd: "/repo",
            state: "working", startedAt: at - 1, lastActivityAt: at,
            tokensSession: 0, tokensLastTurn: 0
        )
    }
}
