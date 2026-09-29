import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class RepositoryCatalogPresentationTests: XCTestCase {
    private func snapshot() -> ProjectMeshSnapshot {
        let id = "scope"
        return .init(type: "mesh.snapshot", sessionId: id, projectId: id,
            project: .init(projectId: id, name: "Workspace", canonicalRepositoryId: "local:/dev", createdAt: 1),
            tasks: [.init(taskId: "stable", projectId: id, title: "Continue", goal: "", state: "working",
                          ownerSessionId: "owner", createdAt: 1, updatedAt: 2)],
            executions: [.init(taskId: "stable", sessionId: "owner", provider: "codex", computerId: "mac",
                               workspace: "/dev", repositoryId: "github.com/one/api", branch: "main", startedAt: 1)],
            claims: [], dependencies: [], events: [], generatedAt: 2)
    }

    func testContextShowsIdentityWithoutUsingChatTitleOrPrivatePaths() {
        var snapshot = snapshot()
        let task = snapshot.tasks[0]
        XCTAssertTrue(RepositoryCatalogPresentation.taskContext(task: task, snapshot: snapshot).contains("github.com/one/api"))
        snapshot.executions[0].endedAt = 3
        snapshot.tasks[0].ownerSessionId = nil
        XCTAssertEqual(RepositoryCatalogPresentation.taskContext(task: snapshot.tasks[0], snapshot: snapshot),
                       String(format: L("Last observed repository: %@"), "github.com/one/api"))
        snapshot.executions[0].repositoryId = nil
        XCTAssertEqual(RepositoryCatalogPresentation.taskContext(task: task, snapshot: snapshot), L("No repository reported"))
        let workspace = RepositoryCatalog.Entry(id: "local:/private/path", name: "Local", isGit: false, memberships: [])
        XCTAssertFalse(RepositoryCatalogPresentation.identity(workspace).contains("/private"))
        let git = RepositoryCatalog.Entry(id: workspace.id, name: "Local", isGit: true, memberships: [])
        XCTAssertEqual(RepositoryCatalogPresentation.identity(git), L("Local Git repository"))
        let remote = RepositoryCatalog.Entry(id: "github.com/one/api", name: "api", isGit: true, memberships: [])
        XCTAssertEqual(RepositoryCatalogPresentation.identity(remote), remote.id)
    }

    func testEveryExecutionRelationIsExplicitAndOnlyMatchingBranchIsUsed() throws {
        let snapshot = snapshot()
        let row = try XCTUnwrap(ProjectMeshRecency.rows(snapshot.tasks, snapshot: snapshot, sessions: []).first)
        for (relation, key) in [(RepositoryCatalog.TaskRelation.current, "Task repository"),
            (.lastObserved, "Last observed repository"), (.previous, "Previous execution"),
            (.multiple, "Multiple repositories reported"), (.unassigned, "No repository reported")] {
            let reference = RepositoryCatalog.TaskReference(row: row, relation: relation)
            XCTAssertEqual(RepositoryCatalogPresentation.relation(reference, repositoryId: "other"), L(key))
            XCTAssertEqual(RepositoryCatalogPresentation.relation(reference, repositoryId: "github.com/one/api"), "\(L(key)) · main")
        }
    }

    func testMeshSummaryDisambiguatesSameNameRepositoriesAndUnknownAssignments() {
        var snapshot = snapshot()
        snapshot.bindings = [.init(bindingId: "second", projectId: snapshot.projectId, endpointId: "mac",
                                  repositoryId: "github.com/two/api", displayName: "api", available: false)]
        let summary = RepositoryCatalogPresentation.meshSummary(snapshot)
        XCTAssertTrue(summary.contains("github.com/one/api"))
        XCTAssertTrue(summary.contains("github.com/two/api"))
        snapshot.executions.append(.init(taskId: "stable", sessionId: "owner", provider: "claude",
            computerId: "other", workspace: "/dev", repositoryId: "github.com/two/api", startedAt: 1))
        XCTAssertTrue(RepositoryCatalogPresentation.taskContext(task: snapshot.tasks[0], snapshot: snapshot).contains(summary))
        snapshot.executions = []
        snapshot.bindings = []
        XCTAssertEqual(RepositoryCatalogPresentation.meshSummary(snapshot), L("Workspace without confirmed Git"))
        let foreign = ProjectMeshTask(taskId: "foreign", projectId: "foreign", title: "", goal: "", state: "planned",
                                     createdAt: 1, updatedAt: 1)
        XCTAssertTrue(ProjectTaskRepositoryGroups.assignment(task: foreign, snapshot: snapshot).repositoryIds.isEmpty)
    }

    func testCatalogViewsPreserveTaskAndMeshStateForMissingAndPartialSnapshots() {
        let model = AppModel()
        RenderProbe.render(NavigationView { RepositoryCatalogListView(model: model) })
        RenderProbe.render(NavigationView { RepositoryCatalogDetailView(repositoryId: "missing", model: model) })
        var snapshot = snapshot()
        snapshot.incomplete = true
        model.meshSnapshots = [snapshot.projectId: snapshot]
        RenderProbe.render(NavigationView { RepositoryCatalogListView(model: model) })
        RenderProbe.render(NavigationView { RepositoryCatalogDetailView(repositoryId: "github.com/one/api", model: model) })
        RenderProbe.render(NavigationView { RepositoryCatalogDetailView(repositoryId: "local:/dev", model: model) })
        XCTAssertEqual(model.meshSnapshots[snapshot.projectId], snapshot)
    }
}
