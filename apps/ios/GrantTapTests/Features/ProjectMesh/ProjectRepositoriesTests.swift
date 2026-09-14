import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class ProjectRepositoriesTests: XCTestCase {
    private func project(_ id: String, name: String, repo: String) -> ProjectMeshProject {
        ProjectMeshProject(projectId: id, name: name, repositoryRoot: "/Users/me/dev/\(name)", canonicalRepositoryId: repo, createdAt: 1)
    }

    private func snapshot() -> ProjectMeshSnapshot {
        let app = project("p-app", name: "nodvox", repo: "github.com/sergii/nodvox")
        var snapshot = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "p-app", projectId: "p-app", project: app,
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1
        )
        snapshot.bindings = [
            ProjectBindingSummary(bindingId: "b1", projectId: "p-app", endpointId: "Mac.lan", repositoryId: "github.com/sergii/nodvox", displayName: "nodvox", available: true),
            ProjectBindingSummary(bindingId: "b2", projectId: "p-app", endpointId: "Air.local", repositoryId: "github.com/sergii/nodvox", displayName: "nodvox", available: false),
            ProjectBindingSummary(bindingId: "b3", projectId: "p-app", endpointId: "Mac.lan", repositoryId: "github.com/sergii/granttap-mcp", displayName: "granttap-mcp", available: true),
            ProjectBindingSummary(bindingId: "b4", projectId: "p-app", endpointId: "Mac.lan", repositoryId: "github.com/sergii/scratch", displayName: "scratch", available: true),
        ]
        snapshot.peers = [
            ProjectIntegrationPeer(projectId: "p-app", repositoryId: "github.com/sergii/nodvox", peer: "granttap-mcp", via: "protocol", relation: "runtime", updatedAt: 1),
            ProjectIntegrationPeer(projectId: "p-app", repositoryId: "github.com/sergii/nodvox", peer: "granttap-mcp", via: "protocol", relation: "runtime", updatedAt: 2),
            ProjectIntegrationPeer(projectId: "p-app", repositoryId: "github.com/sergii/nodvox", peer: "granttap-site", via: "release", relation: "site", updatedAt: 1),
        ]
        snapshot.executions = [
            ExecutionSessionLink(taskId: "t1", sessionId: "s1", provider: "claude", computerId: "Mac.lan", workspace: "/Users/me/dev/nodvox", repositoryId: "github.com/sergii/nodvox", branch: "main", startedAt: 1),
            ExecutionSessionLink(taskId: "t2", sessionId: "s2", provider: "claude", computerId: "Mac.lan", workspace: "/Users/me/dev/nodvox", repositoryId: "github.com/sergii/nodvox", branch: "feat/x", startedAt: 1),
            ExecutionSessionLink(taskId: "t3", sessionId: "s3", provider: "codex", computerId: "Mac.lan", workspace: "/Users/me/dev/granttap-mcp", repositoryId: "github.com/sergii/granttap-mcp", branch: "main", startedAt: 1, endedAt: 2),
            ExecutionSessionLink(taskId: "t4", sessionId: "s4", provider: "codex", computerId: "Mac.lan", workspace: "/Users/me/dev/other", repositoryId: "github.com/sergii/other", startedAt: 1),
        ]
        return snapshot
    }

    func testTheOwnRepositoryComesFirstThenTheMapThenWhatElseWasBound() {
        let mcp = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "p-mcp", projectId: "p-mcp",
            project: project("p-mcp", name: "granttap-mcp", repo: "github.com/sergii/granttap-mcp"),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1
        )
        let rows = ProjectRepositories.rows(snapshot: snapshot(), projects: [snapshot(), mcp])
        XCTAssertEqual(rows.map(\.name), ["nodvox", "granttap-mcp", "granttap-site", "other", "scratch"])
        XCTAssertEqual(rows[0].kind, .own)
        XCTAssertEqual(rows[0].computers.map(\.endpointId), ["Mac.lan", "Air.local"], "available first")
        XCTAssertEqual(rows[0].openTasks, 2)
        XCTAssertEqual(rows[0].branches, ["feat/x", "main"])
        XCTAssertNil(rows[0].projectId)
        XCTAssertEqual(rows[1].kind, .peer(via: "protocol", relation: "runtime", through: nil))
        XCTAssertEqual(rows[1].projectId, "p-mcp", "the peer is a Project on this phone")
        XCTAssertEqual(rows[1].computers.map(\.endpointId), ["Mac.lan"])
        XCTAssertEqual(rows[1].openTasks, 0, "its one execution has ended")
        XCTAssertEqual(rows[2].computers.count, 0)
        XCTAssertNil(rows[2].projectId)
        XCTAssertEqual(rows[3].kind, .seen)
        XCTAssertEqual(rows[3].openTasks, 1)
        XCTAssertEqual(rows[4].kind, .seen)
        XCTAssertEqual(ProjectRepositories.repositoryLeaf("github.com/x/y.git/"), "y")
        XCTAssertTrue(ProjectRepositories.detail(rows[0]).contains("Mac.lan"))
        XCTAssertTrue(ProjectRepositories.detail(rows[0]).contains(L("offline")))
        XCTAssertTrue(ProjectRepositories.detail(rows[2]).contains(L("not bound on any computer")))
        XCTAssertTrue(ProjectRepositories.detail(rows[3]).contains(L("bound here, not in the map")))
        XCTAssertEqual(rows[0], rows[0])
        XCTAssertNotEqual(rows[0], rows[1])
    }

    func testTheSectionRendersWithAndWithoutAMap() {
        let model = AppModel()
        let mcp = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "p-mcp", projectId: "p-mcp",
            project: project("p-mcp", name: "granttap-mcp", repo: "github.com/sergii/granttap-mcp"),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1
        )
        model.meshSnapshots = ["p-app": snapshot(), "p-mcp": mcp]
        RenderProbe.render(NavigationView { List { ProjectRepositoriesSection(snapshot: snapshot(), model: model) } })
        RenderProbe.render(NavigationView { ProjectMeshView(snapshot: snapshot(), model: model) })
        var bare = snapshot()
        bare.peers = nil
        bare.bindings = nil
        RenderProbe.render(NavigationView { List { ProjectRepositoriesSection(snapshot: bare, model: model) } })
        XCTAssertEqual(ProjectRepositories.rows(snapshot: bare, projects: []).map(\.kind), [.own, .seen, .seen])
    }
}
