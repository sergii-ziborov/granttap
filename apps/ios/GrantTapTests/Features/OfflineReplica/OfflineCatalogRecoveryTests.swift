import XCTest
@testable import GrantTap

final class OfflineCatalogRecoveryTests: XCTestCase {
    @MainActor
    func testAccountRecoveryRemovesDemoRowsAndKeepsRealChatsForOfflineRestart() throws {
        let previous = SessionCatalogCache.load()
        SessionCatalogCache.clear()
        defer {
            SessionCatalogCache.clear()
            if let previous { SessionCatalogCache.save(previous) }
        }
        func chat(_ id: String) -> SessionInfo {
            SessionInfo(sessionId: id, agent: "codex", state: "idle", startedAt: 1,
                        lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        }
        let live = chat("offline-live")
        let history = chat("offline-history")
        let demo = chat("granttap-codex-demo")
        SessionCatalogCache.save(.init(sessions: [live, demo], history: [history],
            machine: "Saved Mac", tokensRecent: 42, tokenWindowHours: 24, generatedAt: 2))
        let model = AppModel()
        model.sessions = [live, demo]
        model.sessionHistory = [history]
        model.purgeDemoCatalogResidue(reason: "account-recovery")
        let saved = try XCTUnwrap(SessionCatalogCache.load())
        XCTAssertEqual(saved.sessions.map(\.sessionId), [live.sessionId])
        XCTAssertEqual(saved.history.map(\.sessionId), [history.sessionId])
        XCTAssertEqual(saved.machine, "Saved Mac")
        XCTAssertEqual(saved.tokensRecent, 42)
        let restarted = AppModel()
        restarted.loadCachedSessionCatalogIfNeeded()
        XCTAssertTrue(restarted.relaysByRoom.isEmpty)
        XCTAssertEqual(restarted.sessions.map(\.sessionId), [live.sessionId])
        XCTAssertEqual(restarted.sessionHistory.map(\.sessionId), [history.sessionId])
    }
}
