import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testApprovalReceiveRejectsInFlightAndRecentCancellationCollisions() {
        let model = AppModel()
        model.approvalDecisionSessionScope["in-flight"] = "session-a"
        model.receive(collisionApproval(id: "in-flight", session: "session-b"), fromRoom: "room")
        XCTAssertTrue(model.pending.isEmpty)

        model.recentlyCancelledIds[model.cancellationKey("recent", room: "room")] = Date()
        model.receive(collisionApproval(id: "recent", session: nil), fromRoom: "room")
        XCTAssertTrue(model.pending.isEmpty)

        model.lastCancelAllAtByRoom["room"] = Date()
        model.receive(collisionApproval(
            id: "cancel-all", session: nil,
            createdAt: Date().timeIntervalSince1970 * 1_000
        ), fromRoom: "room")
        XCTAssertTrue(model.pending.isEmpty)
        XCTAssertTrue(model.log.contains { $0.contains("LATE_BLOCKED") })
    }

    @MainActor
    func testResolvedAndCancelEventsFailClosedForWrongRoomsAndDecisionScopes() {
        let model = AppModel()
        model.requestSourceRoom["resolved"] = "expected"
        model.receive(collisionResolved(id: "resolved", session: nil), fromRoom: "other")
        XCTAssertEqual(model.requestSourceRoom["resolved"], "expected")

        model.approvalDecisionSessionScope["resolved"] = "session-a"
        model.receive(collisionResolved(id: "resolved", session: "session-a"), fromRoom: "expected")
        XCTAssertNil(model.approvalDecisionSessionScope["resolved"])

        model.requestSourceRoom["cancel"] = "expected"
        model.receive(ApprovalCancel(
            type: "approval.cancel", requestId: "cancel", cancelAll: false,
            reason: "closed", createdAt: 1
        ), fromRoom: "other")
        XCTAssertEqual(model.requestSourceRoom["cancel"], "expected")
        model.approvalDecisionSessionScope["cancel"] = "session-b"
        model.receive(ApprovalCancel(
            type: "approval.cancel", requestId: "cancel", cancelAll: false,
            reason: "closed", createdAt: 2
        ), fromRoom: "expected")
        XCTAssertNil(model.approvalDecisionSessionScope["cancel"])
    }

    @MainActor
    func testApprovalStatusCoversRoomSessionAndPreviouslyUnmappedRows() {
        let model = AppModel()
        model.requestSourceRoom["foreign"] = "other"
        model.pending = [
            collisionApproval(id: "session", session: "session-a"),
            collisionApproval(id: "unmapped", session: nil),
        ]
        model.receive(ApprovalsStatus(
            type: "approvals.status",
            pending: [
                collisionApproval(id: "foreign", session: nil),
                collisionApproval(id: "session", session: "session-b"),
                collisionApproval(id: "unmapped", session: nil),
            ],
            complete: false,
            covered: [ApprovalStatusScope(requestId: "unmapped", sessionId: nil)],
            actions: nil, generatedAt: 10
        ), fromRoom: "room")
        XCTAssertEqual(model.requestSourceRoom["foreign"], "other")
        XCTAssertEqual(model.requestSourceRoom["unmapped"], "room")
        XCTAssertEqual(model.pending.first { $0.requestId == "session" }?.sessionId, "session-a")
    }

    @MainActor
    func testCancelAllUsesDecisionScopeWhenNoCardCarriesSession() {
        let model = AppModel()
        model.questions = [AgentEvent(
            type: "agent.event", text: "Continue?", requestId: "question",
            kind: "question", sessionId: nil, createdAt: 1
        )]
        model.approvalDecisionSessionScope["question"] = "session-a"
        model.requestSourceRoom["question"] = "room"
        model.clearAllPendingApprovals(reason: "fixture", fromRoom: "room")
        XCTAssertTrue(model.questions.isEmpty)
        XCTAssertNil(model.approvalDecisionSessionScope["question"])
    }

    private func collisionApproval(
        id: String, session: String?, createdAt: Double = 1
    ) -> ApprovalRequest {
        ApprovalRequest(
            type: "approval.request", requestId: id, agent: "codex",
            kind: "permission", tool: "Bash", title: "Run tests",
            command: "npm test", cwd: "/repo", sessionId: session,
            risk: .medium, danger: .caution, createdAt: createdAt
        )
    }

    private func collisionResolved(id: String, session: String?) -> ApprovalResolved {
        ApprovalResolved(
            type: "approval.resolved", requestId: id, status: "applied",
            decision: "allow", decidedBy: "phone", note: nil,
            sessionId: session, nativeUiCleared: true, resolvedAt: 1
        )
    }
}
