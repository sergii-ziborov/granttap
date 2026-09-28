import XCTest
@testable import GrantTap

final class SessionUsageSnapshotTests: XCTestCase {
    private var session: SessionInfo {
        SessionInfo(sessionId: "native", agent: "codex", projectId: "mesh", taskId: "task",
                    computerId: "this-mac", model: "previous", state: "working",
                    startedAt: 100, lastActivityAt: 200, tokensSession: 0, tokensLastTurn: 0)
    }

    func testNativeUsageEnrichesTheSameTaskWithoutReplacingItsIdentity() throws {
        let json = Data(#"{"sessionId":"native","agent":"codex","tokensSession":1200,"tokensLastTurn":120,"model":"observed","contextTokensUsed":600,"contextWindow":200000}"#.utf8)
        let usage = try JSONDecoder().decode(SessionUsageSnapshot.self, from: json)
        let enriched = usage.applying(to: session)
        XCTAssertTrue(usage.isValid)
        XCTAssertEqual(usage.key, "codex\u{1f}native")
        XCTAssertEqual(enriched.tokensSession, 1_200)
        XCTAssertEqual(enriched.tokensLastTurn, 120)
        XCTAssertEqual(enriched.model, "observed")
        XCTAssertEqual(enriched.contextTokensUsed, 600)
        XCTAssertEqual(enriched.contextWindow, 200_000)
        XCTAssertEqual(enriched.projectId, session.projectId)
        XCTAssertEqual(enriched.taskId, session.taskId)
        XCTAssertEqual(enriched.computerId, session.computerId)
        XCTAssertEqual(enriched.state, session.state)
    }

    func testOtherProviderOrSessionCannotSupplyTokens() {
        XCTAssertEqual(SessionUsageSnapshot(sessionId: "other", agent: "codex",
            tokensSession: 99, tokensLastTurn: 1).applying(to: session), session)
        XCTAssertEqual(SessionUsageSnapshot(sessionId: "native", agent: "claude",
            tokensSession: 99, tokensLastTurn: 1).applying(to: session), session)
        let valid = SessionUsageSnapshot(sessionId: "native", agent: "codex",
                                        tokensSession: 99, tokensLastTurn: 1)
        XCTAssertEqual(valid.applying(to: session).model, "previous")
    }

    func testMalformedUsageIsRejectedWithoutOverwritingTheTask() {
        let rows = [
            SessionUsageSnapshot(sessionId: "", agent: "codex", tokensSession: 1, tokensLastTurn: 1),
            SessionUsageSnapshot(sessionId: "native", agent: "", tokensSession: 1, tokensLastTurn: 1),
            SessionUsageSnapshot(sessionId: "native", agent: "codex", tokensSession: -1, tokensLastTurn: 1),
            SessionUsageSnapshot(sessionId: "native", agent: "codex", tokensSession: 1, tokensLastTurn: -1),
            SessionUsageSnapshot(sessionId: "native", agent: "codex", tokensSession: 1, tokensLastTurn: 1,
                                 contextTokensUsed: -1),
            SessionUsageSnapshot(sessionId: "native", agent: "codex", tokensSession: 1, tokensLastTurn: 1,
                                 contextWindow: 0),
            SessionUsageSnapshot(sessionId: "native", agent: "codex", tokensSession: 1, tokensLastTurn: 1,
                                 model: String(repeating: "m", count: 129)),
        ]
        for usage in rows {
            XCTAssertFalse(usage.isValid)
            XCTAssertEqual(usage.applying(to: session), session)
        }
    }
}
