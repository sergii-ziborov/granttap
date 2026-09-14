import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testDecisionDeliveryFailureSuccessAndDuplicateGuards() {
        let model = AppModel()
        let request = decisionRequest(id: "decision-a", sessionId: "session-a")
        model.decide(request, "allow")
        XCTAssertNil(model.approvalDecisionsInFlight[request.requestId])
        XCTAssertTrue(model.log.first?.contains("decision.send failed") == true)

        model.markDecisionInFlight(request.requestId, decision: "allow", sessionId: "session-a")
        let before = model.log.count
        model.decide(request, "deny")
        XCTAssertEqual(model.log.count, before)
        model.finishDecisionDelivery(
            requestId: request.requestId, decision: "allow", by: "phone",
            title: request.title, agent: request.agent, error: nil
        )
        XCTAssertTrue(model.log.first?.contains("waiting for computer") == true)
        model.finishDecisionDelivery(
            requestId: request.requestId, decision: "deny", by: "watch",
            title: request.title, agent: request.agent,
            error: RelaySendError.disconnected
        )
        XCTAssertNil(model.approvalDecisionsInFlight[request.requestId])
    }

    @MainActor
    func testDecisionByIdPinsRoomAndRejectsWrongSessionOrRoom() {
        let model = AppModel()
        let room = "decision-room"
        let request = decisionRequest(id: "decision-b", sessionId: "session-b")
        model.pending = [request]
        model.requestSourceRoom[request.requestId] = room
        model.decideById(
            request.requestId, "allow", by: "notification",
            roomId: "wrong", sessionId: "session-b"
        )
        XCTAssertTrue(model.log.first?.contains("room mismatch") == true)
        model.decideById(
            request.requestId, "allow", by: "notification",
            roomId: room, sessionId: "wrong"
        )
        XCTAssertTrue(model.log.first?.contains("session mismatch") == true)
        model.decideById(
            request.requestId, "allow", by: "notification",
            roomId: room, sessionId: "session-b"
        )
        XCTAssertNil(model.approvalDecisionsInFlight[request.requestId])

        model.decideById(
            "missing", "deny", by: "watch", roomId: room, sessionId: nil
        )
        XCTAssertNil(model.approvalDecisionsInFlight["missing"])
        model.markDecisionInFlight("busy", decision: "allow", sessionId: nil)
        model.decideById("busy", "deny", by: "watch")
        XCTAssertEqual(model.approvalDecisionsInFlight["busy"], "allow")
    }

    @MainActor
    func testQuestionAnswersSeparatePermissionAndCorrelatedMessagePaths() {
        let model = AppModel()
        model.deliveries = []
        let request = decisionRequest(id: "permission", sessionId: "session")
        model.pending = [request]
        for answer in ["yes", "Y", "да", "no", "N", "нет"] {
            model.answerQuestion(request.requestId, answer)
        }
        XCTAssertTrue(model.deliveries.isEmpty)

        model.pending = []
        model.questions = [AgentEvent(
            type: "agent.event", text: "What next?", requestId: "open-question",
            kind: "question", sessionId: "session", createdAt: 1
        )]
        model.answerQuestion("open-question", "  Continue with tests  ")
        XCTAssertEqual(model.deliveries.first?.requestId, "open-question")
        XCTAssertEqual(model.deliveries.first?.sessionId, "session")

        XCTAssertFalse(model.isMcpAskApproval(request))
        XCTAssertTrue(model.isMcpAskApproval(decisionRequest(
            id: "mcp", sessionId: nil, agent: "granttap", tool: "ask_yes_no"
        )))
        XCTAssertTrue(model.isMcpAskApproval(decisionRequest(
            id: "ask", sessionId: nil, agent: "custom", tool: "ask"
        )))
        XCTAssertTrue(model.isMcpOpenAsk(decisionRequest(
            id: "open", sessionId: nil, agent: "custom", tool: "ASK"
        )))

        for index in 0..<105 { model.append("line-\(index)") }
        XCTAssertEqual(model.log.count, 100)
    }

    private func decisionRequest(
        id: String, sessionId: String?, agent: String = "codex", tool: String = "Bash"
    ) -> ApprovalRequest {
        ApprovalRequest(
            type: "approval.request", requestId: id, agent: agent,
            kind: "permission", tool: tool, title: "Run?", command: "npm test",
            cwd: "/repo", sessionId: sessionId, risk: .medium,
            danger: .caution, createdAt: 1
        )
    }
}
