import SwiftUI
import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    private func toolStatus(agents: String) throws -> SessionsStatus {
        let json = """
        {"type":"sessions.status","machine":"MacBook","sessions":[],"tokensRecent":0,
         "tokenWindowHours":12,"generatedAt":1,"agents":\(agents)}
        """
        return try JSONDecoder().decode(SessionsStatus.self, from: Data(json.utf8))
    }

    private var toolFixture: String {
        """
        [{"agent":"claude","installed":true,"hookConfigured":true,"version":"2.1.201",
          "updateCommand":"claude update","newerOnThisMac":"2.1.260"},
         {"agent":"codex","installed":false,"hookConfigured":false},
         {"agent":"grok","installed":true,"hookConfigured":false,"version":"1.0.0",
          "updateCommand":"grok update","updating":true}]
        """
    }

    @MainActor
    func testToolVersionsArriveByComputerAndAnUpdateIsAskedOfThatComputer() throws {
        let model = AppModel()
        model.applySessionsStatus(try toolStatus(agents: toolFixture), sourceNamespace: "room-a")
        let tools = try XCTUnwrap(model.agentIntegrationsByRoom["room-a"])
        XCTAssertEqual(tools.map(\.agent), ["claude", "codex", "grok"])
        XCTAssertEqual(tools[0].newerOnThisMac, "2.1.260")
        XCTAssertEqual(tools[0].updateCommand, "claude update")
        XCTAssertNil(tools[1].version, "a field the computer did not send stays absent")
        XCTAssertEqual(tools[2].updating, true)
        XCTAssertEqual(model.agentIntegrations.count, 3, "the flat list the watch reads is kept")

        // The phone names the tool; the request carries nothing else.
        var sent: ToolUpdate?
        let requestId = try XCTUnwrap(model.updateTool(agent: "claude", room: "room-a") { sent = $0 })
        XCTAssertEqual(sent?.type, "tool.update")
        XCTAssertEqual(sent?.agent, "claude")
        XCTAssertEqual(sent?.requestId, requestId)
        guard case .running = model.toolUpdate(room: "room-a", agent: "claude") else {
            return XCTFail("an asked update is shown as running until the computer answers")
        }
        XCTAssertNil(model.updateTool(agent: "codex", room: "room-none"),
                     "a computer without a link cannot be asked")

        let result = ToolUpdateResult(
            type: "tool.update.result", agent: "claude", requestId: requestId, ok: true,
            before: "2.1.201", after: "2.1.260", command: "claude update",
            message: "Claude Code updated from 2.1.201 to 2.1.260.", output: "Updating to 2.1.260...",
            createdAt: 2
        )
        model.receive(result, fromRoom: "room-a")
        guard case .finished(let finished) = model.toolUpdate(room: "room-a", agent: "claude") else {
            return XCTFail("the computer's answer replaces the running state")
        }
        XCTAssertEqual(finished.after, "2.1.260")
        XCTAssertNil(model.toolUpdate(room: "room-b", agent: "claude"), "another computer's Claude is untouched")

        // Every row state renders: behind, running, current, and finished.
        let names = ["claude", "codex", "cursor", "grok", "other"].map(ToolCatalog.name)
        XCTAssertEqual(names, ["Claude Code", "Codex CLI", "Cursor CLI", "Grok CLI", "other"])
        let finishedRow = ToolVersionRow(info: tools[0], progress: .finished(result), computerName: "MacBook") {}
        XCTAssertFalse(finishedRow.isRunning)
        XCTAssertTrue(finishedRow.subtitle.contains("2.1.260"))
        let runningRow = ToolVersionRow(info: tools[2], progress: nil, computerName: "MacBook") {}
        XCTAssertTrue(runningRow.isRunning, "the computer's own `updating` flag counts")
        XCTAssertEqual(runningRow.subtitle, L("Updating…"))
        let askedRow = ToolVersionRow(info: tools[1], progress: .running(requestId: "r", startedAt: 1), computerName: "MacBook") {}
        XCTAssertTrue(askedRow.isRunning)
        XCTAssertEqual(ToolVersionRow(info: tools[1], progress: nil, computerName: "MacBook") {}.subtitle, L("Not installed."))
        let current = AgentIntegrationInfo(agent: "cursor", installed: true, hookConfigured: true, version: "2026.9.1")
        XCTAssertEqual(ToolVersionRow(info: current, progress: nil, computerName: "MacBook") {}.subtitle,
                       L("Kept current outside GrantTap."))
        let plain = AgentIntegrationInfo(agent: "grok", installed: true, hookConfigured: false,
                                         version: "1.0.0", updateCommand: "grok update")
        XCTAssertEqual(ToolVersionRow(info: plain, progress: nil, computerName: "MacBook") {}.subtitle, "grok update")
        for row in [finishedRow, runningRow, askedRow] { RenderProbe.render(List { row }) }
    }

    /// The computer screen lists a linked computer's tools, and an update asked
    /// there travels over that computer's own link.
    @MainActor
    func testTheComputerScreenListsToolsForALinkedComputer() throws {
        let model = AppModel()
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            .empty, pairing: testPairing(room: "room-a"), prefer: true, now: 1
        )
        model.applySessionsStatus(try toolStatus(agents: toolFixture), sourceNamespace: "room-a")
        let failed = ToolUpdateResult(
            type: "tool.update.result", agent: "claude", requestId: "r", ok: false,
            before: "2.1.201", command: "claude update",
            message: "Claude Code update failed: exited with code 1.", output: "npm ERR! EACCES",
            createdAt: 2
        )
        model.receive(failed, fromRoom: "room-a")
        RenderProbe.render(ConnectionDetailSheet().environmentObject(model))

        model.relaysByRoom["room-a"] = RelayClient(pairing: testPairing(room: "room-a"))
        XCTAssertNotNil(model.updateTool(agent: "grok", room: "room-a"),
                        "with a link, the request goes out over it")
        guard case .running = model.toolUpdate(room: "room-a", agent: "grok") else {
            return XCTFail("asked over the link, shown as running")
        }
        RenderProbe.render(ConnectionDetailSheet().environmentObject(model))
    }
}
