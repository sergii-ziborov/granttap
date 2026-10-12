import XCTest
@testable import GrantTap

@MainActor
final class ApprovalAutomationTests: XCTestCase {
    func testChangingOneChatNeverResumesGlobalAutomationOrChangesGlobalGating() {
        let model = AppModel()
        model.autoAcceptPaused = true
        model.gatingEnabled = false
        let session = SessionInfo(sessionId: "isolated-control", agent: "codex", title: "Test",
            state: "idle", startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        let sheet = ChatCapabilitySheet(sessionId: session.sessionId, session: session,
            rows: [], accent: .blue, model: model, onToggle: { _ in })
        for mode in PersonalApprovalMode.allCases {
            sheet.approvalBinding.wrappedValue = mode
            XCTAssertTrue(model.autoAcceptPaused)
            XCTAssertFalse(model.gatingEnabled)
        }
    }

    func testOnlyTheExactComputerReceiptConfirmsTheRequestedRule() {
        let model = AppModel()
        model.sessionSourceRooms["chat"] = ["computer"]
        model.automationPending["chat"] = "operation"
        model.automationPrevious["chat"] = "ask"
        model.autoAcceptBySession["chat"] = "except_push"
        let applied = ConfigCommandResult(type: "config.command.result", operationId: "operation",
            ok: true, reason: nil, sessionId: "chat", level: "except_push", revision: 3, createdAt: 1)
        model.receiveAutomationResult(applied, fromRoom: "other")
        XCTAssertEqual(model.automationPending["chat"], "operation")
        model.receiveAutomationResult(applied, fromRoom: "computer")
        XCTAssertNil(model.automationPending["chat"])
        XCTAssertNil(model.automationPrevious["chat"])
        XCTAssertEqual(model.autoAcceptBySession["chat"], "except_push")
    }

    func testRejectionAndTimeoutRestoreThePreviousConfirmedState() {
        let model = AppModel()
        model.sessionSourceRooms["chat"] = ["computer"]
        model.automationPending["chat"] = "operation"
        model.automationPrevious["chat"] = "ask"
        model.autoAcceptBySession["chat"] = "full"
        model.receiveAutomationResult(.init(type: "config.command.result", operationId: "operation",
            ok: false, reason: "stale_instance", sessionId: "chat", level: nil, revision: nil,
            createdAt: 1), fromRoom: "computer")
        XCTAssertEqual(model.autoAcceptBySession["chat"], "ask")
        XCTAssertNotNil(model.automationErrors["chat"])
        model.automationPrevious["chat"] = ""
        model.automationPending["chat"] = "again"
        model.failAutomation("chat", message: "No receipt")
        XCTAssertNil(model.autoAcceptBySession["chat"])
        XCTAssertNil(model.automationPending["chat"])
        XCTAssertEqual(model.automationErrors["chat"], "No receipt")
    }

    func testStructuredQuestionsRequirePhoneAnswersInsteadOfWatchPermissionTaps() {
        let model = AppModel()
        model.pending = [AppModelDemoFixtures.claudeQuestion(at: 1)]
        let attention = model.humanAttentionItems.first
        XCTAssertEqual(attention?.kind, .question)
        XCTAssertEqual(attention?.action, .openPhone)
    }

    func testFreshCommandRetainsAnExplicitClearAndComputerEpoch() throws {
        let value = ConfigSet(type: "config.set", enabled: nil, excludeSession: nil,
            includeSession: nil, autoAcceptDefault: nil,
            autoAcceptSession: .init(sessionId: "chat", level: nil, authorizeProjectAsk: true),
            autoAcceptPaused: nil, createdAt: 1_000)
        let bytes = try XCTUnwrap(RelayClient.freshConfigurationPayload(value,
            instanceEpoch: "current-computer", operationId: "operation"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(body["operationId"] as? String, "operation")
        XCTAssertEqual(body["instanceEpoch"] as? String, "current-computer")
        XCTAssertEqual(body["expiresAt"] as? Double, 61_000)
        let action = try XCTUnwrap(body["autoAcceptSession"] as? [String: Any])
        XCTAssertTrue(action["level"] is NSNull)
        XCTAssertEqual(action["authorizeProjectAsk"] as? Bool, true)
    }
}
