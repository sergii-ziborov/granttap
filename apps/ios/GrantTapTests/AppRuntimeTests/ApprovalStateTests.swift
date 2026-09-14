import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testApprovalReceiveRedeliveryAndResolutionStayRoomAndSessionScoped() {
        let model = AppModel()
        let scope = UUID().uuidString
        let requestId = "approval-\(scope)"
        let room = "room-\(scope)"
        let otherRoom = "other-room-\(scope)"
        let original = approvalRequest(id: requestId, sessionId: "session-a")
        model.receive(original, fromRoom: room)
        XCTAssertEqual(model.pending.map(\.requestId), [requestId])
        XCTAssertEqual(model.requestSourceRoom[requestId], room)

        model.receive(approvalRequest(
            id: requestId, sessionId: "session-a", title: "Updated"
        ), fromRoom: room)
        XCTAssertEqual(model.pending.first?.title, "Updated")
        model.receive(original, fromRoom: otherRoom)
        model.receive(approvalRequest(
            id: requestId, sessionId: "other-session"
        ), fromRoom: room)
        XCTAssertEqual(model.pending.count, 1)

        model.receive(ApprovalResolved(
            type: "approval.resolved", requestId: requestId, status: "applied",
            decision: "allow", decidedBy: "phone", note: nil,
            sessionId: "other-session", nativeUiCleared: true, resolvedAt: 30
        ), fromRoom: room)
        XCTAssertEqual(model.pending.count, 1)
        model.receive(ApprovalResolved(
            type: "approval.resolved", requestId: requestId, status: "applied",
            decision: "allow", decidedBy: "phone", note: nil,
            sessionId: "session-a", nativeUiCleared: true, resolvedAt: 31
        ), fromRoom: room)
        XCTAssertTrue(model.pending.isEmpty)

        model.receive(original, fromRoom: room)
        XCTAssertTrue(model.pending.isEmpty)
    }

    @MainActor
    func testApprovalStatusRemovesOnlyExplicitlyCoveredStaleScopes() {
        let model = AppModel()
        let stale = approvalRequest(id: "stale", sessionId: "session-a", createdAt: 10)
        let current = approvalRequest(id: "current", sessionId: "session-b", createdAt: 11)
        model.receive(stale, fromRoom: "room-a")
        model.receive(current, fromRoom: "room-a")

        model.receive(ApprovalsStatus(
            type: "approvals.status", pending: [current], complete: false,
            covered: [
                ApprovalStatusScope(requestId: "stale", sessionId: "session-a"),
                ApprovalStatusScope(requestId: "current", sessionId: "session-b"),
            ], actions: nil, generatedAt: 20
        ), fromRoom: "room-a")
        XCTAssertEqual(model.pending.map(\.requestId), ["current"])

        let legacy = approvalRequest(id: "legacy", sessionId: nil, createdAt: 21)
        model.receive(ApprovalsStatus(
            type: "approvals.status", pending: [legacy], complete: true,
            covered: nil, actions: nil, generatedAt: 22
        ), fromRoom: "room-a")
        XCTAssertTrue(model.pending.contains { $0.requestId == "legacy" })

        model.receive(ApprovalsStatus(
            type: "approvals.status", pending: [], complete: false,
            covered: [], actions: nil, generatedAt: 19
        ), fromRoom: "room-a")
        XCTAssertFalse(model.pending.isEmpty)
    }

    @MainActor
    func testApprovalCancelOneCancelAllAndLegacyDecisionPaths() {
        let model = AppModel()
        let scope = UUID().uuidString
        let room = "room-\(scope)"
        let firstId = "first-\(scope)"
        let secondId = "second-\(scope)"
        let first = approvalRequest(id: firstId, sessionId: "session-a")
        let second = approvalRequest(id: secondId, sessionId: "session-b")
        model.receive(first, fromRoom: room)
        model.receive(second, fromRoom: room)
        model.focusedApprovalId = firstId

        model.receive(ApprovalCancel(
            type: "approval.cancel", requestId: firstId, cancelAll: false,
            reason: "native closed", createdAt: 20
        ), fromRoom: room)
        XCTAssertEqual(model.pending.map(\.requestId), [secondId])
        XCTAssertNil(model.focusedApprovalId)
        model.receive(first, fromRoom: room)
        XCTAssertEqual(model.pending.map(\.requestId), [secondId])

        model.receive(ApprovalCancel(
            type: "approval.cancel", requestId: nil, cancelAll: true,
            reason: "shutdown", createdAt: 21
        ), fromRoom: room)
        XCTAssertTrue(model.pending.isEmpty)
        model.receiveRemoteDecision(ApprovalDecision(
            type: "approval.decision", requestId: "old", decision: "deny",
            note: nil, decidedBy: "watch", sessionId: nil, decidedAt: 22
        ), fromRoom: room)

        model.receive(ApprovalCancel(
            type: "approval.cancel", requestId: nil, cancelAll: false,
            reason: nil, createdAt: 23
        ), fromRoom: room)
        XCTAssertTrue(AppModel.isShellishQuestion("Allow Bash?"))
        XCTAssertTrue(AppModel.isShellishQuestion("Cursor shell request"))
        XCTAssertFalse(AppModel.isShellishQuestion("What should I do?"))
    }

    private func approvalRequest(
        id: String, sessionId: String?, title: String = "Run tests?",
        createdAt: Double = 10
    ) -> ApprovalRequest {
        ApprovalRequest(
            type: "approval.request", requestId: id, agent: "codex",
            kind: "permission", tool: "Bash", title: title,
            command: "npm test", cwd: "/repo", sessionId: sessionId,
            risk: .medium, danger: .caution, createdAt: createdAt
        )
    }
}
