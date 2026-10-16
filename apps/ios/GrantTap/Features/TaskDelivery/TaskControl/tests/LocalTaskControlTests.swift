#if targetEnvironment(macCatalyst)
import XCTest
@testable import GrantTap

@MainActor
final class LocalTaskControlTests: XCTestCase {
    private var session: SessionInfo {
        SessionInfo(sessionId: "s", agent: "codex", projectId: "p", taskId: "t", computerId: "mac",
            cwd: "/synthetic", state: "working", startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
    }

    func testLocalMessagePreservesAllNextTurnOptions() async throws {
        var input: [String: Any] = [:]
        let result = try await MacLocalMCPClient.send(socketPath: "/unused", projectId: "p", taskId: "t",
            sessionId: "s", text: "Synthetic", deliveryId: UUID(), model: "gpt-6-sol", effort: "ultra",
            preferredMcp: "fixture", skill: "review", permissionMode: "plan") { operation, request in
                XCTAssertEqual(operation, "desktop.task_send")
                input = request
                return Data(#"{"operation":"desktop.task_send","accepted":true}"#.utf8)
            }
        XCTAssertTrue(result.accepted)
        XCTAssertEqual(input["permission_mode"] as? String, "plan")
        XCTAssertEqual(input["effort"] as? String, "ultra")
        XCTAssertEqual(input["skill"] as? String, "review")
        XCTAssertEqual(input["preferred_mcp"] as? String, "fixture")
        XCTAssertEqual(input["session_id"] as? String, "s")
    }

    func testControlsKeepExactTaskAndValidateConfirmation() async throws {
        let reply = try await MacLocalTaskCommands.control(session, action: "resume", continue: true) { operation, input in
            XCTAssertEqual(operation, "desktop.task_control")
            XCTAssertEqual(input["project_id"] as? String, "p")
            XCTAssertEqual(input["task_id"] as? String, "t")
            XCTAssertEqual(input["session_id"] as? String, "s")
            XCTAssertEqual(input["continue"] as? Bool, true)
            return Data(#"{"operation":"desktop.task_control","result":{"type":"session.control.result","sessionId":"s","action":"resume","ok":true,"message":"Resumed","createdAt":1}}"#.utf8)
        }
        let result = try JSONDecoder().decode(SessionControlResult.self, from: reply)
        XCTAssertTrue(result.ok)
        do {
            _ = try await MacLocalTaskCommands.control(session, action: "pause") { _, _ in
                Data(#"{"operation":"desktop.task_control","result":{"type":"session.control.result","sessionId":"other","action":"pause","ok":true,"message":"Paused","createdAt":1}}"#.utf8)
            }
            XCTFail("Another chat's confirmation must be refused")
        } catch { XCTAssertTrue(error is MacLocalMCPError) }
    }

    func testOnlyConfirmedPreferencesChangeChatState() async throws {
        let model = AppModel()
        model.sessions = [session]
        let result = try await MacLocalTaskCommands.preferences(session, changes: ["access_level": "read-only"]) { _, input in
            XCTAssertEqual(input["access_level"] as? String, "read-only")
            XCTAssertEqual(input["task_id"] as? String, "t")
            return Data(#"{"operation":"desktop.task_preferences","accepted":true,"session_id":"s","paused":true,"excluded":false,"level":"ask","access_level":"read-only","shell_allowed":false,"mcp_disabled":[],"skills_disabled":[]}"#.utf8)
        }
        model.applyLocalTaskPreferences(result, sessionId: "other")
        XCTAssertFalse(model.sessions[0].isPaused)
        model.applyLocalTaskPreferences(result, sessionId: "s")
        XCTAssertTrue(model.sessions[0].isPaused)
        XCTAssertEqual(model.sessions[0].accessLevel, "read-only")
        XCTAssertEqual(model.sessions[0].shellAllowed, false)
        XCTAssertEqual(model.autoAcceptBySession["s"], "ask")
        let paused = TaskChatView(session: model.sessions[0], modelOverride: model)
        XCTAssertEqual(paused.chatSendAvailability?.blocksSending, true)
    }

    func testLocalCatalogMakesMCPAndSkillsAvailableWithoutChangingAnotherTask() async throws {
        let tools = try await MacLocalTaskCommands.capabilities(session) { operation, input in
            XCTAssertEqual(operation, "desktop.task_capabilities")
            XCTAssertEqual(input["session_id"] as? String, "s")
            return Data(#"{"operation":"desktop.task_capabilities","project_id":"p","task_id":"t","session_id":"s","mcp_servers":[{"name":"fixture","configuredEnabled":true,"allowed":false}],"skills":[{"name":"review","allowed":true}],"shell_allowed":true}"#.utf8)
        }
        let enriched = tools.applying(to: session)
        XCTAssertEqual(enriched.mcpServers?.first?.name, "fixture")
        XCTAssertEqual(enriched.mcpServers?.first?.allowed, false)
        XCTAssertEqual(enriched.skills?.first?.name, "review")
        var other = session
        other.taskId = "other"
        XCTAssertNil(tools.applying(to: other).mcpServers)
    }
}
#endif
