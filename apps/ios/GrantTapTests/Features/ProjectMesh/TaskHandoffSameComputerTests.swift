import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class TaskHandoffSameComputerTests: XCTestCase {
    private let now = 1_800_000_000_000.0

    override func setUp() {
        super.setUp()
        ProjectMeshPersistence.clear()
        AgentMeshPreferencesStore.save(.defaults)
    }

    override func tearDown() {
        ProjectMeshPersistence.clear()
        AgentMeshPreferencesStore.save(.defaults)
        super.tearDown()
    }

    private func linked(_ room: String) -> LinkedComputer {
        LinkedComputer(id: room, pairing: PairingFixture.pairing(room: room), label: room.capitalized, addedAt: now, lastCatalogAt: now, lastMachineName: "\(room).lan")
    }

    private func session() -> SessionInfo {
        SessionInfo(sessionId: "claude", agent: "claude", projectId: "project", taskId: "task", title: "Move me",
                    cwd: "/repo", branch: "main", state: "idle", startedAt: now - 1_000, lastActivityAt: now, tokensSession: 1, tokensLastTurn: 1)
    }

    private func snapshot(uncommitted: Bool) -> ProjectMeshSnapshot {
        ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "nodvox", repositoryRoot: "/repo", canonicalRepositoryId: "github.com/x/nodvox", createdAt: 1),
            tasks: [.init(taskId: "task", projectId: "project", title: "Move me", goal: "g", state: "working", ownerSessionId: "claude", createdAt: 1, updatedAt: 2)],
            executions: [.init(taskId: "task", sessionId: "claude", provider: "claude", computerId: "source.lan", workspace: "/repo",
                               branch: "main", uncommitted: uncommitted, startedAt: 1)],
            claims: [], dependencies: [], events: [], generatedAt: now
        )
    }

    private func model(rooms: [String], uncommitted: Bool = false) -> AppModel {
        let model = AppModel()
        model.agentMeshPreferences = .defaults
        model.meshSnapshots = ["project": snapshot(uncommitted: uncommitted)]
        model.connectionRegistry = .init(connections: rooms.map(linked), preferredId: "source")
        model.sessionSourceRooms["claude"] = ["source"]
        return model
    }

    func testThisComputerIsADestinationForAnotherAgent() {
        let model = model(rooms: ["source", "target"])
        let sheet = TaskHandoffSheet(session: session(), model: model, initialTargetRoom: "source", initialTargetProvider: "codex")
        XCTAssertEqual(sheet.targets.map(\.id), ["source", "target"], "this computer reads first")
        XCTAssertTrue(sheet.staysHere)
        XCTAssertFalse(sheet.sameAgentHere)
        XCTAssertTrue(sheet.isReady)
        XCTAssertTrue(sheet.performHandoff(targetRoom: "source", targetProvider: "codex"))

        let same = TaskHandoffSheet(session: session(), model: model, initialTargetRoom: "source", initialTargetProvider: "claude")
        XCTAssertTrue(same.sameAgentHere)
        XCTAssertFalse(same.performHandoff(targetRoom: "source", targetProvider: "claude"), "the same agent on the same computer is no move")
        XCTAssertEqual(same.defaultSelection.room, "target", "another computer is preferred when there is one")
        RenderProbe.render(same)
        RenderProbe.render(sheet)
    }

    func testAloneWithOneComputerTheTaskStillMovesBetweenAgents() {
        let model = model(rooms: ["source"], uncommitted: true)
        let sheet = TaskHandoffSheet(session: session(), model: model)
        XCTAssertEqual(sheet.defaultSelection.room, "source")
        XCTAssertEqual(sheet.defaultSelection.provider, "codex")
        XCTAssertTrue(sheet.hasUncommittedWork)
        XCTAssertFalse(sheet.isReady, "uncommitted work still blocks a move within one computer")
        RenderProbe.render(sheet)

        let capabilities = ChatCapabilitySheet(sessionId: "claude", session: session(), rows: [], accent: .red, model: model) { _ in }
        RenderProbe.render(capabilities.environmentObject(model))
    }

    func testAPushIsAskedForOnlyWhenTheTaskLeavesTheComputer() {
        let model = model(rooms: ["source", "target"])
        var sent: [ProjectMeshHandoffPrepare] = []
        model.prepareTaskHandoff(session: session(), targetProvider: "codex", targetComputer: "target.lan", checkpoint: true, push: true)
        let request = ProjectMeshHandoffPrepare(type: "mesh.handoff.prepare", sessionId: "claude", projectId: "project", taskId: "task",
                                                targetProvider: "codex", targetComputer: "target.lan", createdAt: now, checkpoint: true, push: true)
        sent.append(request)
        let encoded = try? RelayClient.encodeOmittingNulls(request)
        let object = (try? JSONSerialization.jsonObject(with: encoded ?? Data())) as? [String: Any]
        XCTAssertEqual(object?["push"] as? Bool, true)
        let plain = ProjectMeshHandoffPrepare(type: "mesh.handoff.prepare", sessionId: "claude", projectId: "project", taskId: "task",
                                              targetProvider: "codex", targetComputer: "source.lan", createdAt: now)
        let plainObject = (try? JSONSerialization.jsonObject(with: (try? RelayClient.encodeOmittingNulls(plain)) ?? Data())) as? [String: Any]
        XCTAssertNil(plainObject?["push"])
        XCTAssertNil(plainObject?["checkpoint"])
        XCTAssertEqual(sent.count, 1)
    }
}
