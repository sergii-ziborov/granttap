import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testArchiveRestoreAndListFallbacksPreserveSnapshots() {
        let defaults = UserDefaults.standard.object(forKey: "granttap.archived-sessions")
        let stored = ArchivedSessionPersistence.load()
        defer {
            if let defaults {
                UserDefaults.standard.set(defaults, forKey: "granttap.archived-sessions")
            } else {
                UserDefaults.standard.removeObject(forKey: "granttap.archived-sessions")
            }
            ArchivedSessionPersistence.save(stored)
        }
        let model = AppModel()
        model.archivedSessionIds = []
        model.archivedSessions = [:]
        let older = archiveSession("older", at: 1)
        let newer = archiveSession("newer", at: 2)
        model.sessions = [older, newer]

        model.setSessionArchived(older.sessionId, true)
        model.setSessionArchived(newer.sessionId, true)
        model.setSessionArchived("missing", true)
        XCTAssertTrue(model.isArchived(older.sessionId))
        XCTAssertEqual(model.sessionsForArchiveView(true).map(\.sessionId), ["newer", "older"])
        XCTAssertEqual(model.sessionsForArchiveView(false).map(\.sessionId), ["newer", "older"])

        model.sessions = []
        model.sessionHistory = []
        model.setSessionArchived(older.sessionId, false)
        XCTAssertEqual(model.sessions.first?.sessionId, older.sessionId)
        model.setSessionArchived("missing", false)

        model.archivedSessions[newer.sessionId] = newer
        model.sessions = [newer]
        model.setSessionArchived(newer.sessionId, false)
        XCTAssertEqual(model.sessions.filter { $0.sessionId == newer.sessionId }.count, 1)

        model.sessions = []
        model.sessionHistory = (0..<30).map { archiveSession("history-\($0)", at: Double($0)) }
        XCTAssertEqual(model.sessionsForArchiveView(false).count, 24)
    }

    @MainActor
    func testArchiveProjectionDeduplicationCapabilitiesAndWorkspaces() {
        let model = AppModel()
        var old = archiveSession("same", at: 1)
        old.cwd = "/repo/one"
        var fresh = archiveSession("same", at: 3)
        fresh.cwd = "/repo/two"
        let other = archiveSession("other", at: 2, agent: "claude")
        let deduped = AppModel.deduplicatedSessions([old, fresh, other, old])
        XCTAssertEqual(deduped.map(\.sessionId), ["same", "other"])
        XCTAssertEqual(deduped.first?.lastActivityAt, 3)

        old.mcpServers = [McpServerInfo(name: "github", configuredEnabled: true, allowed: true)]
        old.skills = [SkillInfo(name: "documents", allowed: true)]
        old.shellAllowed = false
        var lean = fresh
        lean.mcpServers = []
        lean.skills = nil
        lean.shellAllowed = nil
        let retained = AppModel.retainingCapabilities(incoming: lean, previous: old)
        XCTAssertEqual(retained.mcpServers?.first?.name, "github")
        XCTAssertEqual(retained.skills?.first?.name, "documents")
        XCTAssertEqual(retained.shellAllowed, false)
        XCTAssertEqual(AppModel.retainingCapabilities(incoming: fresh, previous: nil), fresh)

        model.sessions = [fresh]
        model.sessionHistory = [fresh, old, other, archiveSession("archived", at: 9)]
        model.archivedSessionIds = ["archived"]
        XCTAssertEqual(model.allSessionHistory.map(\.sessionId), ["other"])
        var blank = archiveSession("blank", at: 4)
        blank.cwd = "  "
        model.sessionHistory = []
        model.archivedSessionIds = []
        model.archivedSessions = ["copy": fresh, "blank": blank]
        XCTAssertEqual(model.workspaceFolders(for: "CODEX"), ["/repo/two"])
        XCTAssertTrue(model.workspaceFolders(for: "cursor").isEmpty)
    }

    @MainActor
    func testAttemptDeliveryFailsClosedAndQueuesOfflineRoutes() throws {
        let model = AppModel()
        var delivered = existingSessionDelivery(createdAt: 1, id: "done")
        delivered.state = .delivered
        var rejected = existingSessionDelivery(createdAt: 1, id: "rejected")
        rejected.admissionRejected = true
        var deferred = existingSessionDelivery(createdAt: 1, id: "deferred")
        deferred.awaitingSessionRemap = true
        model.deliveries = [delivered, rejected, deferred]
        for id in ["missing", "done", "rejected", "deferred"] { model.attemptDelivery(id) }
        XCTAssertEqual(model.deliveries.map(\.attempts), [1, 1, 1])

        var unknown = existingSessionDelivery(createdAt: 1, id: "unknown")
        unknown.roomId = nil
        model.deliveries = [unknown]
        model.attemptDelivery(unknown.id)
        XCTAssertEqual(model.deliveries.first?.state, .failed)

        var removed = existingSessionDelivery(createdAt: 1, id: "removed")
        removed.roomId = "removed-room"
        model.deliveries = [removed]
        model.attemptDelivery(removed.id)
        XCTAssertTrue(model.deliveries.first?.error?.contains("removed") == true)

        model.connectionRegistry = testConnectionRegistry()
        var offline = existingSessionDelivery(createdAt: 1, id: "offline")
        offline.roomId = nil
        offline.nextRetryAt = 2
        offline.attemptGeneration = "generation"
        model.deliveries = [offline]
        model.attemptDelivery(offline.id)
        XCTAssertEqual(model.deliveries.first?.roomId, "room-a")
        XCTAssertEqual(model.deliveries.first?.state, .queued)
        XCTAssertNil(model.deliveries.first?.nextRetryAt)
        XCTAssertNil(model.deliveries.first?.attemptGeneration)
    }

    @MainActor
    func testAttemptDeliveryMaxAttemptsLiveSendAndKnownSessionSelection() async throws {
        let model = AppModel()
        model.connectionRegistry = testConnectionRegistry()
        model.roomRuntime["room-a"] = AppModel.RoomRuntime(socketUp: true)
        model.relaysByRoom["room-a"] = RelayClient(pairing: testPairing())
        model.activities = [:]
        let now = Date().timeIntervalSince1970 * 1_000
        var exhausted = existingSessionDelivery(
            createdAt: now, id: "exhausted", sessionId: "exhausted-session"
        )
        exhausted.attempts = model.maxDeliveryAttempts
        model.deliveries = [exhausted]
        model.attemptDelivery(exhausted.id)
        XCTAssertEqual(model.deliveries.first?.state, .failed)
        XCTAssertTrue(model.deliveries.first?.error?.contains("five attempts") == true)

        var reflected = existingSessionDelivery(
            createdAt: now, id: "reflected", text: "sent", sessionId: "reflected-session"
        )
        reflected.attempts = model.maxDeliveryAttempts
        model.activities["reflected-session"] = SessionActivity(
            sessionId: "reflected-session", agent: "codex", state: "idle",
            entries: [ActivityEntry(id: "provider", kind: "user", text: "sent", createdAt: now)],
            generatedAt: now
        )
        model.deliveries = [reflected]
        model.attemptDelivery(reflected.id)
        XCTAssertTrue(model.deliveries.isEmpty)

        var live = existingSessionDelivery(createdAt: now, id: "live", agent: "claude")
        live.attempts = 0
        live.state = .queued
        model.deliveries = [live]
        model.attemptDelivery(live.id)
        XCTAssertEqual(model.deliveries.first?.attempts, 1)
        XCTAssertNotNil(model.deliveries.first?.attemptGeneration)
        await Task.yield()
        await Task.yield()

        let codex = archiveSession("alias", at: 1)
        let claude = archiveSession("native", at: 2, agent: "claude")
        model.sessions = [codex]
        model.sessionHistory = [claude]
        model.sessionIdAliases = ["alias": "native"]
        XCTAssertEqual(model.knownSession(for: "alias", preferredAgent: "CLAUDE")?.agent, "claude")
        XCTAssertEqual(model.knownSession(for: "alias", preferredAgent: "cursor")?.sessionId, "alias")
        XCTAssertNil(model.knownSession(for: "absent", preferredAgent: nil))
    }

    @MainActor
    func testPruneTransitionsExpiredOriginsAndDropsOrphanedReplies() {
        let model = AppModel()
        let now = Date().timeIntervalSince1970 * 1_000
        model.localOnlySessionIds = ["local", "local-old"]
        var terminal = existingSessionDelivery(
            createdAt: now, id: "terminal", sessionId: "local"
        )
        terminal.processingAcknowledgedAt = now - DeliveryOutboxPolicy.terminalLifecycleMs - 1
        terminal.attemptGeneration = "terminal-generation"
        model.liveDeliveryAttemptGenerations = ["terminal-generation"]
        var follower = existingSessionDelivery(
            createdAt: now, id: "follower", sessionId: "local"
        )
        follower.state = .queued
        follower.awaitingSessionRemap = true
        var held = existingSessionDelivery(
            createdAt: now - DeliveryOutboxPolicy.maximumLocalRetentionMs - 1,
            id: "held", sessionId: "stub"
        )
        held.state = .queued
        held.awaitingSessionRemap = true
        var localOld = existingSessionDelivery(
            createdAt: now, id: "local-old", sessionId: "local-old"
        )
        localOld.state = .queued
        localOld.awaitingSessionRemap = false
        localOld.updatedAt = now - DeliveryOutboxPolicy.maximumLocalRetentionMs - 1
        var orphan = existingSessionDelivery(
            createdAt: now - 16_000, id: "orphan", requestId: "gone"
        )
        orphan.state = .sending
        let noSession = OutgoingDelivery(
            id: "no-session", text: "reply", agent: nil, cwd: nil, sessionId: nil,
            requestId: nil, roomId: "room-a", attachments: [], preferredMcp: nil,
            skill: nil, createdAt: now - 9_000, updatedAt: now - 9_000,
            attempts: 1, state: .failed, error: "failed", nextRetryAt: nil
        )
        model.deliveries = [terminal, follower, held, localOld, orphan, noSession]

        model.pruneStaleDeliveries()

        XCTAssertFalse(model.liveDeliveryAttemptGenerations.contains("terminal-generation"))
        XCTAssertEqual(model.deliveries.first { $0.id == "terminal" }?.state, .failed)
        XCTAssertEqual(model.deliveries.first { $0.id == "follower" }?.state, .failed)
        XCTAssertEqual(model.deliveries.first { $0.id == "held" }?.state, .failed)
        XCTAssertEqual(model.deliveries.first { $0.id == "local-old" }?.state, .failed)
        XCTAssertNil(model.deliveries.first { $0.id == "orphan" })
        XCTAssertNil(model.deliveries.first { $0.id == "no-session" })
    }

    @MainActor
    func testRetryAndVisibleDeliveryProjectionCoverAliasesRoomsAndRetention() {
        let model = AppModel()
        let now = Date().timeIntervalSince1970 * 1_000
        model.connectionRegistry = testConnectionRegistry()
        model.sessionIdAliases = ["old": "native", "older": "old"]
        model.rememberSessionSourceRoom("room-a", sessionId: "native")
        var retry = existingSessionDelivery(
            createdAt: now, id: "retry", sessionId: "native"
        )
        retry.state = .failed
        retry.awaitingSessionRemap = true
        retry.attemptGeneration = "retry-generation"
        model.liveDeliveryAttemptGenerations = ["retry-generation"]
        model.deliveries = [retry]
        model.retryDelivery(retry.id)
        XCTAssertEqual(model.deliveries.first?.state, .queued)
        XCTAssertEqual(model.deliveries.first?.awaitingSessionRemap, false)
        XCTAssertNil(model.deliveries.first?.attemptGeneration)

        var visible = existingSessionDelivery(
            createdAt: now, id: "visible", sessionId: "old"
        )
        visible.state = .queued
        visible.attempts = 0
        var delivered = visible
        delivered.state = .delivered
        var wrongRoom = visible
        wrongRoom.roomId = "room-b"
        var unrelated = visible
        unrelated = OutgoingDelivery(
            id: "unrelated", text: "x", agent: nil, cwd: nil, sessionId: "other",
            requestId: nil, roomId: "room-a", attachments: [], preferredMcp: nil,
            skill: nil, createdAt: now, updatedAt: now, attempts: 0,
            state: .queued, error: nil, nextRetryAt: nil
        )
        var acknowledged = visible
        acknowledged.processingAcknowledgedAt = now
        acknowledged.attempts = 1
        model.deliveries = [visible, delivered, wrongRoom, unrelated, acknowledged]
        let result = model.deliveries(for: "native")
        XCTAssertEqual(result.map(\.id), ["visible", "visible"])
        XCTAssertTrue(model.deliveries(for: nil).isEmpty)
    }

    @MainActor
    func testClearStuckRepliesKeepsOnlyActiveRequestRows() {
        let model = AppModel()
        var active = existingSessionDelivery(createdAt: 1, id: "active", requestId: "request")
        active.state = .sending
        active.attempts = 1
        var delivered = active
        delivered.state = .delivered
        var failed = active
        failed.state = .failed
        var exhausted = active
        exhausted.attempts = model.maxDeliveryAttempts
        let ordinary = existingSessionDelivery(createdAt: 1, id: "ordinary")
        model.deliveries = [active, delivered, failed, exhausted, ordinary]
        model.clearStuckMcpReplies()
        XCTAssertEqual(model.deliveries.map(\.id), ["active", "ordinary"])
    }

    private func archiveSession(
        _ id: String, at: Double, agent: String = "codex"
    ) -> SessionInfo {
        SessionInfo(
            sessionId: id, agent: agent, title: id, cwd: "/repo/\(id)",
            state: "idle", startedAt: at - 1, lastActivityAt: at,
            tokensSession: 0, tokensLastTurn: 0
        )
    }
}
