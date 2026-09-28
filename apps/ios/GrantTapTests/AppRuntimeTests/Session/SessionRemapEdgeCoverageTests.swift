import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testLocalStubFallbackUsesDeliverySessionAgentAndNewestRow() {
        let model = AppModel()
        model.localOnlySessionIds = ["claude-local", "codex-local"]
        model.sessions = [
            remapSession(id: "codex-local", agent: "codex", at: 20),
            remapSession(id: "claude-local", agent: "claude", at: 10),
        ]
        var delivery = existingSessionDelivery(
            createdAt: 1, id: "agent-fallback", sessionId: "claude-local"
        )
        delivery.state = .failed
        model.deliveries = [delivery]
        XCTAssertEqual(model.resolveLocalStubForAdoption(hintAgent: nil), "claude-local")

        model.deliveries = []
        model.sessions = [
            remapSession(id: "codex-local", agent: "codex", at: 20),
            remapSession(id: "claude-local", agent: "claude", at: 10),
        ]
        XCTAssertEqual(model.resolveLocalStubForAdoption(hintAgent: nil), "codex-local")
    }

    @MainActor
    func testRemapCollapsesAliasesMergesActivityAndMovesSubscribers() {
        let model = AppModel()
        model.connectionRegistry = testConnectionRegistry()
        model.localOnlySessionIds = ["old"]
        model.sessionIdAliases = ["older": "old"]
        model.sessionToOpen = "old"
        model.sessions = [remapSession(id: "old", agent: "codex", at: 1)]
        model.activities = [
            "old": remapActivity(id: "old", entry: "old-entry", at: 4),
            "native": remapActivity(id: "native", entry: "native-entry", at: 3),
        ]
        model.activitySubscribers["old"] = ["screen", "watch"]

        model.remapLocalSession(from: "old", to: "native")

        XCTAssertEqual(model.sessionIdAliases["older"], "native")
        XCTAssertEqual(model.sessionToOpen, "native")
        XCTAssertEqual(model.activities["native"]?.entries.count, 2)
        XCTAssertEqual(model.activitySubscribers["native"], ["screen", "watch"])
    }

    @MainActor
    func testRemapMovesActivityWhenNativeTaskHasNoExistingTimeline() {
        let model = AppModel()
        model.localOnlySessionIds = ["old"]
        model.activities["old"] = remapActivity(id: "old", entry: "only", at: 2)
        model.remapLocalSession(from: "old", to: "native")
        XCTAssertNil(model.activities["old"])
        XCTAssertEqual(model.activities["native"]?.sessionId, "native")
        XCTAssertEqual(model.activities["native"]?.entries.first?.id, "only")
    }

    private func remapSession(id: String, agent: String, at: Double) -> SessionInfo {
        SessionInfo(
            sessionId: id, agent: agent, title: id, state: "working",
            startedAt: at, lastActivityAt: at, tokensSession: 0, tokensLastTurn: 0
        )
    }

    private func remapActivity(id: String, entry: String, at: Double) -> SessionActivity {
        SessionActivity(
            sessionId: id, agent: "codex", state: "working",
            entries: [ActivityEntry(id: entry, kind: "message", text: entry, createdAt: at)],
            generatedAt: at
        )
    }
}
