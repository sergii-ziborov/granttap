import XCTest
@testable import GrantTap

@MainActor
final class ChatApprovalPreferencesTests: XCTestCase {
    func testFullAndCustomRulesAreNeverMisreportedAsTheRecommendedMode() {
        let model = AppModel()
        let session = SessionInfo(sessionId: "approval-preview", agent: "codex", title: "Test",
            state: "idle", startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        let controls = ChatCapabilitySheet(sessionId: session.sessionId, session: session,
            rows: [], accent: .blue, model: model, onToggle: { _ in })
        model.autoAcceptBySession[session.sessionId] = "full"
        XCTAssertEqual(controls.approvalBinding.wrappedValue.rawValue, "full")
        model.autoAcceptBySession[session.sessionId] = "safe"
        XCTAssertEqual(controls.approvalBinding.wrappedValue.rawValue, "custom")
    }

    func testQuickChoiceUsesTheSameScopedRuleAndReceiptAsTaskControls() throws {
        for agent in ["codex", "claude", "cursor", "grok"] {
            let model = AppModel()
            let session = SessionInfo(sessionId: "approval-\(agent)", agent: agent, title: "Test",
                accessLevel: "read-only", state: "idle", startedAt: 1, lastActivityAt: 2,
                tokensSession: 0, tokensLastTurn: 0)
            let pairing = PairingFixture.pairing(room: "approval-test")
            model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: pairing)
            model.relaysByRoom[pairing.room] = RelayClient(pairing: pairing)
            model.sessionSourceRooms[session.sessionId] = [pairing.room]
            model.sessions = [session]
            model.autoAcceptDefault = "safe"
            model.autoAcceptBySession["other-chat"] = "ask"
            let preferences = ChatApprovalPreferences(sessionId: session.sessionId, session: session, model: model)
            let controls = ChatCapabilitySheet(sessionId: session.sessionId, session: session,
                rows: [], accent: .blue, model: model, onToggle: { _ in })
            for (mode, level) in [(PersonalApprovalMode.every, "ask"), (.risky, "except_push"), (.full, "full")] {
                preferences.apply(mode)
                XCTAssertEqual(model.automationDesired[session.sessionId], level)
                XCTAssertEqual(controls.approvalBinding.wrappedValue, mode)
                let operation = try XCTUnwrap(model.automationPending[session.sessionId])
                model.receiveAutomationResult(.init(type: "config.command.result", operationId: operation,
                    ok: true, reason: nil, sessionId: session.sessionId, level: level,
                    revision: 1, createdAt: 1), fromRoom: pairing.room)
                XCTAssertNil(model.automationPending[session.sessionId])
                XCTAssertEqual(preferences.mode, mode)
                XCTAssertEqual(model.autoAcceptDefault, "safe")
                XCTAssertEqual(model.autoAcceptBySession["other-chat"], "ask")
                XCTAssertEqual(model.sessions.first?.accessLevel, "read-only")
            }
            preferences.apply(.defaults)
            XCTAssertTrue(model.isExcluded(session.sessionId))
            XCTAssertEqual(controls.approvalBinding.wrappedValue, .defaults)
            XCTAssertEqual(model.autoAcceptBySession["other-chat"], "ask")
        }
    }

    func testUnavailableComputerAndCustomSelectionCannotGrantPermissions() {
        let model = AppModel()
        let session = SessionInfo(sessionId: "offline", agent: "codex", title: "Test",
            state: "idle", startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        model.gatingEnabled = false
        model.autoAcceptPaused = true
        let preferences = ChatApprovalPreferences(sessionId: session.sessionId, session: session, model: model)
        for choice in PersonalApprovalMode.allCases { preferences.apply(choice) }
        XCTAssertTrue(model.autoAcceptBySession.isEmpty)
        XCTAssertTrue(model.automationPending.isEmpty)
        XCTAssertFalse(model.isExcluded(session.sessionId))
        XCTAssertFalse(model.gatingEnabled)
        XCTAssertTrue(model.autoAcceptPaused)
    }
}
