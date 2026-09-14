import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testCachedCatalogRejectsDemoAndRestoresRealRowsWithMetadata() {
        let stored = SessionCatalogCache.load()
        SessionCatalogCache.clear()
        defer {
            SessionCatalogCache.clear()
            if let stored {
                SessionCatalogCache.save(
                    sessions: stored.sessions, history: stored.history,
                    machine: stored.machine, tokensRecent: stored.tokensRecent,
                    tokenWindowHours: stored.tokenWindowHours, generatedAt: stored.generatedAt
                )
            }
        }
        let model = AppModel()
        let demo = catalogSession(id: AppModelDemoFixtures.codexSessionId, at: 10)
        SessionCatalogCache.save(
            sessions: [demo], history: [], machine: "Demo", tokensRecent: 1,
            tokenWindowHours: 12, generatedAt: 10
        )
        model.loadCachedSessionCatalogIfNeeded()
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertTrue(model.log.first?.contains("discarded") == true)

        let live = catalogSession(id: "cached-live", at: 20)
        let history = catalogSession(id: "cached-history", at: 15)
        SessionCatalogCache.save(
            sessions: [demo, live, live], history: [history], machine: "Review Mac",
            tokensRecent: 42, tokenWindowHours: 24, generatedAt: 21
        )
        model.loadCachedSessionCatalogIfNeeded()
        XCTAssertEqual(model.sessions.map(\.sessionId), ["cached-live"])
        XCTAssertEqual(model.sessionHistory.map(\.sessionId), ["cached-history"])
        XCTAssertEqual(model.machineName, "Review Mac")
        XCTAssertEqual(model.tokensRecent, 42)
        model.loadCachedSessionCatalogIfNeeded()
        model.clearLocalSessionCache()
        XCTAssertTrue(model.sessions.isEmpty)
    }

    @MainActor
    func testSessionsStatusRetainsCapabilitiesLocalStubsAndAllSettings() {
        let model = AppModel()
        let now = Date().timeIntervalSince1970 * 1_000
        var previous = catalogSession(id: "live", at: now - 10)
        previous.mcpServers = [McpServerInfo(
            name: "github", configuredEnabled: true, allowed: false
        )]
        previous.skills = [SkillInfo(name: "documents", allowed: false)]
        let local = catalogSession(id: "local-stub", at: now)
        model.sessions = [previous, local]
        model.localOnlySessionIds = [local.sessionId]
        model.lastSessionsGeneratedAt = now
        model.archivedSessionIds = ["archived"]
        model.archivedSessions = [:]
        var lean = catalogSession(id: "live", at: now)
        lean.mcpServers = nil
        lean.skills = nil
        let archived = catalogSession(id: "archived", at: now - 1)
        let activity = SessionActivity(
            sessionId: "live", agent: "codex", state: "working",
            entries: [ActivityEntry(id: "event", kind: "message", text: "Fresh", createdAt: now)],
            generatedAt: now
        )
        model.applySessionsStatus(SessionsStatus(
            machine: "Review Mac", sessions: [lean, lean], history: [archived, lean],
            activities: [activity], tokensRecent: 500, tokenWindowHours: 8,
            gatingEnabled: false, excludedSessions: ["live"],
            autoAcceptDefault: "ask", autoAcceptBySession: ["live": "full"],
            autoAcceptPaused: true, globalMcpDisabled: ["github"],
            globalSkillsDisabled: ["documents"], globalShellDisabled: true,
            agents: [AgentIntegrationInfo(agent: "codex", installed: true, hookConfigured: true)],
            generatedAt: now
        ))
        XCTAssertEqual(Set(model.sessions.map(\.sessionId)), ["live", "local-stub"])
        XCTAssertEqual(model.sessions.first { $0.sessionId == "live" }?.mcpServers?.first?.allowed,
                       false)
        XCTAssertEqual(model.activities["live"]?.entries.first?.text, "Fresh")
        XCTAssertNotNil(model.archivedSessions["archived"])
        XCTAssertFalse(model.gatingEnabled)
        XCTAssertEqual(model.autoAcceptDefault, "ask")
        XCTAssertTrue(model.autoAcceptPaused)
        XCTAssertTrue(model.globalMcpDisabled.contains("github"))
        XCTAssertTrue(model.globalSkillsDisabled.contains("documents"))
        XCTAssertTrue(model.globalShellDisabled)
        XCTAssertEqual(model.agentIntegrations.count, 1)

        model.applySessionsStatus(SessionsStatus(
            machine: "Review Mac", sessions: [], history: nil,
            tokensRecent: 0, tokenWindowHours: 12, generatedAt: now + 1
        ))
        XCTAssertFalse(model.sessions.isEmpty)
        let historyOnly = catalogSession(id: "history-only", at: now + 2)
        model.sessions = []
        model.applySessionsStatus(SessionsStatus(
            machine: "Review Mac", sessions: [], history: [historyOnly],
            tokensRecent: 0, tokenWindowHours: 12, generatedAt: now + 2
        ))
        XCTAssertEqual(model.sessions.first?.sessionId, "history-only")
    }

    @MainActor
    func testSessionsStatusKeepsUntitledCodexUUIDRoutable() {
        let model = AppModel()
        let now = Date().timeIntervalSince1970 * 1_000
        let sessionId = "01a0483d-88a9-7303-bddb-829d110713ae"
        let session = SessionInfo(
            sessionId: sessionId, agent: "codex", title: nil, cwd: "/repo",
            state: "idle", startedAt: now - 60_000, lastActivityAt: now,
            tokensSession: 10, tokensLastTurn: 2
        )

        model.applySessionsStatus(SessionsStatus(
            machine: "Mac", sessions: [session], history: [session],
            tokensRecent: 10, tokenWindowHours: 12, generatedAt: now
        ))

        XCTAssertEqual(model.sessions.map(\.sessionId), [sessionId])
        XCTAssertEqual(model.sessions.first?.displayTitle, L("Untitled chat"))
    }

    @MainActor
    func testLocalSessionCreationAndAdoptionUseDeterministicPriority() {
        let model = AppModel()
        let minted = model.ensureLocalSession(
            sessionId: nil, agent: "codex", cwd: "/repo", title: "First", at: 1
        )
        XCTAssertTrue(model.localOnlySessionIds.contains(minted))
        _ = model.ensureLocalSession(
            sessionId: minted, agent: "codex", cwd: "/other", title: "Second", at: 2
        )
        XCTAssertEqual(model.sessions.first?.title, "First")
        XCTAssertEqual(model.sessions.first?.cwd, "/repo")

        model.sessionToOpen = minted
        XCTAssertEqual(model.resolveLocalStubForAdoption(hintAgent: nil), minted)
        model.adoptMacSessionId("native", agent: "codex")
        XCTAssertEqual(model.resolvedSessionId(minted), "native")
        XCTAssertEqual(model.sessions.first?.sessionId, "native")
        model.adoptMacSessionId("native", agent: "codex")

        let first = model.ensureLocalSession(
            sessionId: nil, agent: "claude", cwd: nil, title: "Claude", at: 3
        )
        let second = model.ensureLocalSession(
            sessionId: nil, agent: "codex", cwd: nil, title: "Codex", at: 4
        )
        model.sessionToOpen = nil
        var delivery = existingSessionDelivery(
            createdAt: 5, id: "adopt", sessionId: first, agent: "claude"
        )
        delivery.state = .queued
        model.deliveries = [delivery]
        XCTAssertEqual(model.resolveLocalStubForAdoption(hintAgent: nil), first)
        model.deliveries = []
        XCTAssertEqual(model.resolveLocalStubForAdoption(hintAgent: "codex"), second)
        model.localOnlySessionIds = [first]
        XCTAssertEqual(model.resolveLocalStubForAdoption(hintAgent: nil), first)
    }

    private func catalogSession(id: String, at: Double) -> SessionInfo {
        SessionInfo(
            sessionId: id, agent: "codex", title: "Task \(id)", cwd: "/repo",
            state: "working", startedAt: at - 10, lastActivityAt: at,
            tokensSession: 10, tokensLastTurn: 2
        )
    }
}
