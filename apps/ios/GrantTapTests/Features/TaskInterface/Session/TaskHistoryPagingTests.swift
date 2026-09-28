import XCTest
@testable import GrantTap

@MainActor
final class TaskHistoryPagingTests: XCTestCase {
    private func session(_ id: String, at time: Double) -> SessionInfo {
        SessionInfo(
            sessionId: id, agent: "codex", state: "idle", startedAt: time,
            lastActivityAt: time, tokensSession: 0, tokensLastTurn: 0
        )
    }

    func testHistoryPagesKeepOlderRowsAcrossStatusRefreshAndRejectWrongRoom() {
        let model = AppModel()
        model.connectionRegistry.preferredId = "preferred-room"
        model.sessionHistory = [session("new", at: 30)]
        model.historyPagingByRoom["preferred-room"] = HistoryPagingState(
            pendingRequestId: "00000000-0000-4000-8000-000000000001"
        )
        let page = SessionsHistoryPage(
            type: "sessions.history.page", requestId: "00000000-0000-4000-8000-000000000001",
            sessions: [session("old", at: 10)], nextCursor: "next", hasMore: true,
            sourceLimited: nil, resetRequired: nil, generatedAt: 40
        )
        model.receiveSessionsHistoryPage(page, fromRoom: "other-room")
        XCTAssertEqual(model.allSessionHistory.map(\.sessionId), ["new"])
        model.receiveSessionsHistoryPage(page, fromRoom: "preferred-room")
        XCTAssertEqual(model.allSessionHistory.map(\.sessionId), ["new", "old"])
        model.sessionHistory = [session("newer", at: 50)]
        XCTAssertEqual(model.allSessionHistory.map(\.sessionId), ["newer", "old"])
        model.receiveSessionsHistoryPage(page, fromRoom: "preferred-room")
        XCTAssertEqual(model.allSessionHistory.map(\.sessionId), ["newer", "old"])
    }
}
