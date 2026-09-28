import XCTest
@testable import GrantTap

final class DesktopCatalogSourcesTests: XCTestCase {
    func testLocalRefreshKeepsRemoteComputerAndReplacesOldLocalRows() {
        let remote = session("pc", computer: "remote", project: "remote-project")
        let old = session("old", computer: "local", project: "local-project")
        let fresh = session("new", computer: "local", project: "local-project")
        let result = DesktopCatalogSources.sessions(local: [fresh], current: [remote, old],
                                                    remoteSessionIds: ["pc"])
        XCTAssertEqual(result.map(\.sessionId), ["pc", "new"])
        XCTAssertEqual(DesktopCatalogSources.sessions(local: [], current: result,
                                                      remoteSessionIds: ["pc"]), [remote])
    }

    func testRemoteNativeIdCollisionCannotTurnIntoALocalSend() {
        let local = session("same", computer: "local", project: "p")
        let remote = session("same", computer: "remote", project: "p")
        XCTAssertEqual(DesktopCatalogSources.sessions(local: [local], current: [remote],
                                                      remoteSessionIds: ["same"]), [remote])
        let execution = ExecutionSessionLink(taskId: "t", sessionId: "same", provider: "codex",
                                              computerId: "local", workspace: "/test",
                                              activeAt: 2, startedAt: 1)
        XCTAssertTrue(DesktopCatalogSources.matches(local, projectId: "p", execution: execution))
        XCTAssertFalse(DesktopCatalogSources.matches(remote, projectId: "p", execution: execution))
        var wrong = session("same", computer: "local", project: "p", agent: "claude")
        XCTAssertFalse(DesktopCatalogSources.matches(wrong, projectId: "p", execution: execution))
        wrong = local
        wrong.taskId = "other-task"
        XCTAssertFalse(DesktopCatalogSources.matches(wrong, projectId: "p", execution: execution))
        wrong = local
        wrong.projectId = "other-project"
        XCTAssertFalse(DesktopCatalogSources.matches(wrong, projectId: "p", execution: execution))
    }

    func testFreshLocalObservationReplacesStaleRelayProjectForTheSameComputer() {
        var remote = session("same", computer: "local", project: "dev")
        remote.lastActivityAt = 1
        remote.state = "finished"
        var local = session("same", computer: "local", project: "repository-mesh")
        local.state = "working"
        let rows = DesktopCatalogSources.sessions(local: [local], current: [remote],
                                                  remoteSessionIds: ["same"])
        XCTAssertEqual(rows, [local])
        XCTAssertEqual(rows.first?.projectId, "repository-mesh")
        XCTAssertEqual(rows.first?.state, "working")
    }

    func testOlderOrDifferentProviderLocalObservationCannotReplaceRelayState() {
        let remote = session("same", computer: "local", project: "reported")
        var local = session("same", computer: "local", project: "stale")
        local.lastActivityAt = 1
        XCTAssertEqual(DesktopCatalogSources.sessions(local: [local], current: [remote],
                                                      remoteSessionIds: ["same"]), [remote])
        local = session("same", computer: "local", project: "stale", agent: "claude")
        local.lastActivityAt = 3
        XCTAssertEqual(DesktopCatalogSources.sessions(local: [local], current: [remote],
                                                      remoteSessionIds: ["same"]), [remote])
    }

    func testLocalRefreshKeepsRemoteMeshAndDropsRemovedLocalMesh() {
        let remote = snapshot("remote")
        let fresh = snapshot("fresh")
        let result = DesktopCatalogSources.snapshots(local: ["fresh": fresh],
            current: ["remote": remote, "old-local": snapshot("old-local")],
            previousLocalIds: ["old-local"], remoteProjectIds: ["remote"], nowMs: 2)
        XCTAssertEqual(Set(result.keys), ["remote", "fresh"])
        XCTAssertEqual(result["remote"], remote)
    }

    func testSameMeshPreservesExecutionsFromBothComputers() {
        var local = snapshot("shared")
        var remote = snapshot("shared")
        local.executions = [.init(taskId: "t", sessionId: "local", provider: "codex",
                                   computerId: "local", workspace: "/local", startedAt: 1)]
        remote.executions = [.init(taskId: "t", sessionId: "remote", provider: "claude",
                                    computerId: "remote", workspace: "/remote", startedAt: 1)]
        let result = DesktopCatalogSources.snapshots(local: ["shared": local],
            current: ["shared": remote], previousLocalIds: ["shared"],
            remoteProjectIds: ["shared"], nowMs: 2)
        XCTAssertEqual(Set(result["shared"]!.executions.map(\.computerId)), ["local", "remote"])
    }

    private func session(_ id: String, computer: String, project: String, agent: String = "codex") -> SessionInfo {
        SessionInfo(sessionId: id, agent: agent, projectId: project, taskId: "t",
                    computerId: computer, state: "idle", startedAt: 1, lastActivityAt: 2,
                    tokensSession: 0, tokensLastTurn: 0)
    }
    private func snapshot(_ id: String) -> ProjectMeshSnapshot {
        ProjectMeshSnapshot(type: "mesh.snapshot", sessionId: id, projectId: id,
            project: .init(projectId: id, name: id, repositoryRoot: nil,
                           canonicalRepositoryId: "repo/\(id)", createdAt: 1),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1)
    }
}
