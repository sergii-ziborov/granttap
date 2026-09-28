import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testTaskConfigurationMutatesOnlyAnExactlyRoutedSession() {
        let model = AppModel()
        let room = "config-\(UUID().uuidString)"
        let sessionId = "session-\(UUID().uuidString)"
        let client = RelayClient(pairing: testPairing(room: room))
        var session = SessionInfo(
            sessionId: sessionId, agent: "codex", title: "Config task",
            state: "working", startedAt: 10, lastActivityAt: 10,
            tokensSession: 0, tokensLastTurn: 0
        )
        session.mcpServers = [McpServerInfo(
            name: "github", configuredEnabled: true, allowed: true
        )]
        session.skills = [SkillInfo(name: "documents", allowed: true)]
        model.sessions = [session]
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            .empty, pairing: testPairing(room: room)
        )
        model.relaysByRoom[room] = client
        model.rememberSessionSourceRoom(room, sessionId: sessionId)

        model.setGating(false)
        model.setSessionExcluded(sessionId, true)
        XCTAssertTrue(model.isExcluded(sessionId))
        model.setSessionExcluded(sessionId, false)
        XCTAssertFalse(model.isExcluded(sessionId))

        model.setAutoAcceptDefault("invalid")
        model.setAutoAcceptDefault("safe")
        model.setAutoAcceptPaused(true)
        XCTAssertEqual(model.autoAcceptLevel(for: sessionId), "ask")
        model.setAutoAcceptPaused(false)
        model.setSessionAutoAccept(sessionId, "full")
        XCTAssertEqual(model.autoAcceptLevel(for: sessionId), "full")
        model.clearSessionAutoAccept(sessionId)
        XCTAssertEqual(model.autoAcceptLevel(for: sessionId), "safe")

        model.setSessionAccess(sessionId, "invalid")
        model.setSessionAccess(sessionId, "workspace")
        model.setSessionMcpAllowed(sessionId, serverName: "github", allowed: false)
        model.setSessionSkillAllowed(sessionId, skillName: "documents", allowed: false)
        model.setSessionSkillAllowed(sessionId, skillName: "ios-qa", allowed: true)
        model.setSessionShellAllowed(sessionId, allowed: false)
        model.compactSession(sessionId)
        model.compactSession(sessionId)

        guard let updated = model.sessions.first else {
            return XCTFail("configured session disappeared")
        }
        XCTAssertEqual(updated.accessLevel, "workspace")
        XCTAssertEqual(updated.mcpServers?.first?.allowed, false)
        XCTAssertEqual(updated.skills?.count, 2)
        XCTAssertEqual(updated.shellAllowed, false)
        XCTAssertTrue(model.compactingSessions.contains(sessionId))
    }

    @MainActor
    func testConfigurationFailsClosedAndExercisesGlobalRoutes() {
        let model = AppModel()
        let sessionId = "blocked-\(UUID().uuidString)"
        model.setSessionExcluded(sessionId, true)
        model.setSessionAutoAccept(sessionId, "ask")
        model.clearSessionAutoAccept(sessionId)
        model.setSessionAccess(sessionId, "full")
        model.setSessionMcpAllowed(sessionId, serverName: "github", allowed: true)
        model.setSessionSkillAllowed(sessionId, skillName: "documents", allowed: true)
        model.setSessionShellAllowed(sessionId, allowed: true)
        model.compactSession(sessionId)
        model.setGlobalMcpAllowed("github", allowed: false)
        model.setGlobalSkillAllowed("documents", allowed: false)
        model.setGlobalShellAllowed(false)
        XCTAssertFalse(model.log.isEmpty)

        let room = "global-\(UUID().uuidString)"
        let client = RelayClient(pairing: testPairing(room: room))
        var registry = ConnectionRegistryLogic.upsert(
            .empty, pairing: testPairing(room: room)
        )
        registry = ConnectionRegistryLogic.noteCatalog(
            registry, roomId: room,
            generatedAt: Date().timeIntervalSince1970 * 1_000,
            machineName: "Test Mac"
        )
        model.connectionRegistry = registry
        model.roomRuntime[room] = AppModel.RoomRuntime(socketUp: true)
        model.relaysByRoom[room] = client
        model.relay = client
        model.connected = true

        model.setGlobalMcpAllowed("github", allowed: false)
        model.setGlobalMcpAllowed("github", allowed: true)
        model.setGlobalMcpAllowed("github", allowed: false, roomId: room)
        model.setGlobalSkillAllowed("documents", allowed: false)
        model.setGlobalSkillAllowed("documents", allowed: true)
        model.setGlobalSkillAllowed("documents", allowed: false, roomId: room)
        model.setGlobalShellAllowed(false)
        model.setGlobalShellAllowed(true)
        XCTAssertFalse(model.globalShellDisabled)
    }

    @MainActor
    func testTaskConfigurationMutatesHistoryAndArchiveWithoutMovingThem() {
        let model = AppModel()
        let room = "stored-config"
        let client = RelayClient(pairing: testPairing(room: room))
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            .empty, pairing: testPairing(room: room)
        )
        model.relaysByRoom[room] = client
        var history = SessionInfo(
            sessionId: "history-config", agent: "codex", title: "History",
            state: "idle", startedAt: 1, lastActivityAt: 2,
            tokensSession: 0, tokensLastTurn: 0
        )
        history.skills = []
        var archived = history
        archived = SessionInfo(
            sessionId: "archive-config", agent: "claude", title: "Archive",
            state: "idle", startedAt: 1, lastActivityAt: 2,
            tokensSession: 0, tokensLastTurn: 0
        )
        model.sessionHistory = [history]
        model.archivedSessions = [archived.sessionId: archived]
        model.rememberSessionSourceRoom(room, sessionId: history.sessionId)
        model.rememberSessionSourceRoom(room, sessionId: archived.sessionId)

        model.setSessionSkillAllowed(history.sessionId, skillName: "review", allowed: false)
        model.setSessionShellAllowed(archived.sessionId, allowed: false)
        XCTAssertEqual(model.sessionHistory[0].skills?.first?.name, "review")
        XCTAssertEqual(model.archivedSessions[archived.sessionId]?.shellAllowed, false)
        XCTAssertTrue(model.sessions.isEmpty)
    }
}
