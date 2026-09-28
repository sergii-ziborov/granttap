import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class ProjectTaskRepositoryGroupsTests: XCTestCase {
    private func workspace() -> ProjectMeshSnapshot {
        ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "workspace", projectId: "workspace",
            project: .init(projectId: "workspace", name: "dev", repositoryRoot: "/dev",
                           canonicalRepositoryId: "local:/dev", createdAt: 1),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1
        )
    }

    private func task(_ id: String, owner: String? = nil) -> ProjectMeshTask {
        .init(taskId: id, projectId: "workspace", title: id, goal: "", state: "working",
              ownerSessionId: owner, createdAt: 1, updatedAt: 1)
    }

    private func execution(
        _ task: String, _ session: String, repo: String?, ended: Double? = nil
    ) -> ExecutionSessionLink {
        .init(taskId: task, sessionId: session, provider: "codex", computerId: "mac",
              workspace: "/dev", repositoryId: repo, startedAt: 1, endedAt: ended)
    }

    func testRefreshAutomaticallyPartitionsWorkspaceTasksByObservedRepository() throws {
        var snapshot = workspace()
        snapshot.tasks = [task("a", owner: "sa"), task("b", owner: "sb"), task("unknown")]
        snapshot.executions = [execution("a", "sa", repo: "github.com/owner/a"),
                               execution("b", "sb", repo: "github.com/owner/b")]
        let original = snapshot
        let first = ProjectTaskRepositoryGroups.make(snapshot: snapshot, sessions: [])
        XCTAssertEqual(first.map(\.title), ["a", "b", L("Workspace tasks")])
        XCTAssertEqual(first.map { $0.rows.map(\.task.taskId) }, [["a"], ["b"], ["unknown"]])
        snapshot.tasks.append(task("new", owner: "sn"))
        snapshot.executions.append(execution("new", "sn", repo: "github.com/owner/b"))
        let second = ProjectTaskRepositoryGroups.make(snapshot: snapshot, sessions: [])
        XCTAssertEqual(second.first { $0.repositoryId == "github.com/owner/b" }?.rows.map(\.task.taskId), ["b", "new"])
        XCTAssertEqual(original.tasks[0].taskId, snapshot.tasks[0].taskId)
        XCTAssertEqual(original.tasks[0].projectId, snapshot.tasks[0].projectId)
        XCTAssertEqual(original.executions, Array(snapshot.executions.prefix(2)))
        XCTAssertEqual(original.bindings, snapshot.bindings)
        XCTAssertEqual(original.events, snapshot.events)
    }

    func testOwnerRepositoryWinsOverHistoryAndChangesAutomaticallyAfterHandoff() throws {
        var snapshot = workspace()
        snapshot.tasks = [task("stable", owner: "new")]
        snapshot.executions = [execution("stable", "old", repo: "github.com/owner/a", ended: 2),
                               execution("stable", "new", repo: "github.com/owner/b")]
        XCTAssertEqual(ProjectTaskRepositoryGroups.make(snapshot: snapshot, sessions: []).first?.repositoryId,
                       "github.com/owner/b")
        snapshot.tasks[0].ownerSessionId = "old"
        XCTAssertEqual(ProjectTaskRepositoryGroups.make(snapshot: snapshot, sessions: []).first?.repositoryId,
                       "github.com/owner/a")
        XCTAssertEqual(snapshot.executions.count, 2)
    }

    func testAmbiguousAndMissingEvidenceStaySeparateWithoutGuessingFromTitleOrPath() {
        var snapshot = workspace()
        snapshot.tasks = [task("ambiguous"), task("unknown"), task("local"), task("only-history")]
        snapshot.tasks[1].title = "Work on project a in /dev/a"
        snapshot.executions = [
            execution("ambiguous", "a", repo: "github.com/owner/a", ended: 2),
            execution("ambiguous", "b", repo: "github.com/owner/b", ended: 3),
            execution("unknown", "no-repo", repo: nil),
            execution("local", "local", repo: "local:/dev/unconfirmed"),
            execution("only-history", "history", repo: "github.com/owner/a", ended: 2),
            execution("foreign-task", "foreign", repo: "github.com/owner/unrelated"),
        ]
        let groups = ProjectTaskRepositoryGroups.make(snapshot: snapshot, sessions: [])
        XCTAssertEqual(groups.map(\.title), ["a", L("Multiple repositories"), L("Workspace tasks")])
        XCTAssertEqual(groups.map { $0.rows.map(\.task.taskId) },
                       [["only-history"], ["ambiguous"], ["local", "unknown"]])
        XCTAssertTrue(ProjectTaskRepositoryGroups.isWorkspace(snapshot))
    }

    func testGitEvidenceIncludingEmptyGitRepositoryReclassifiesLocalWorkspace() {
        var snapshot = workspace()
        snapshot.tasks = [task("stable", owner: "owner")]
        snapshot.executions = [execution("stable", "owner", repo: "local:/dev")]
        XCTAssertTrue(ProjectTaskRepositoryGroups.isWorkspace(snapshot))
        snapshot.executions[0].worktree = "/dev"
        XCTAssertFalse(ProjectTaskRepositoryGroups.isWorkspace(snapshot), "Git need not have a first commit")
        XCTAssertEqual(ProjectTaskRepositoryGroups.make(snapshot: snapshot, sessions: []).map(\.title), [L("Tasks")])
        snapshot.executions[0].worktree = nil
        snapshot.bindings = [.init(bindingId: "binding", projectId: "workspace", endpointId: "mac",
                                   repositoryId: "local:/dev", displayName: "dev", available: false,
                                   revision: "verified-head")]
        XCTAssertFalse(ProjectTaskRepositoryGroups.isWorkspace(snapshot), "offline evidence is retained")
        snapshot.bindings?[0] = .init(bindingId: "foreign", projectId: "foreign", endpointId: "mac",
                                    repositoryId: "local:/dev", displayName: "dev", available: true,
                                    revision: "verified-head")
        XCTAssertTrue(ProjectTaskRepositoryGroups.isWorkspace(snapshot), "foreign records do not classify this Mesh")
    }

    func testConflictingOwnerReportsAreAmbiguousAndIterationOrderDoesNotChangeGrouping() {
        var snapshot = workspace()
        snapshot.tasks = [task("stable", owner: "owner")]
        snapshot.executions = [execution("stable", "owner", repo: "github.com/owner/a"),
                               execution("stable", "owner", repo: "github.com/owner/b")]
        snapshot.executions[1] = .init(
            taskId: "stable", sessionId: "owner", provider: "codex", computerId: "pc",
            workspace: "/other", repositoryId: "github.com/owner/b", startedAt: 2
        )
        let first = ProjectTaskRepositoryGroups.make(snapshot: snapshot, sessions: [])
        snapshot.executions.reverse()
        XCTAssertEqual(first.map(\.id), ProjectTaskRepositoryGroups.make(snapshot: snapshot, sessions: []).map(\.id))
        XCTAssertEqual(first.first?.title, L("Multiple repositories"))
        snapshot.executions[0].endedAt = 3
        XCTAssertEqual(ProjectTaskRepositoryGroups.make(snapshot: snapshot, sessions: []).first?.repositoryId,
                       "github.com/owner/a", "current owner report wins over the closed copy")
    }

    func testTaskSectionsRenderWorkspaceAndRepositoryAndKeepOriginalTaskRoute() {
        let model = AppModel()
        var snapshot = workspace()
        snapshot.tasks = [task("stable", owner: "owner"), task("unknown")]
        snapshot.executions = [execution("stable", "owner", repo: "github.com/owner/a")]
        RenderProbe.render(NavigationView {
            List { ProjectRepositoryTaskSections(snapshot: snapshot, model: model) }
        })
        RenderProbe.render(NavigationView { ProjectMeshView(snapshot: snapshot, model: model) })
        XCTAssertEqual(model.meshSnapshots.count, 0, "presentation does not create or move Projects")
    }

    func testWorkspaceRepositoryRowsAreObservationsWithoutReverseDependency() {
        var snapshot = workspace()
        snapshot.tasks = [task("stable", owner: "owner")]
        snapshot.executions = [execution("stable", "owner", repo: "github.com/owner/a")]
        snapshot.bindings = [.init(bindingId: "a", projectId: "workspace", endpointId: "mac",
                                   repositoryId: "github.com/owner/a", displayName: "a", available: true)]
        let repository = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "repo", projectId: "repo",
            project: .init(projectId: "repo", name: "a", canonicalRepositoryId: "github.com/owner/a", createdAt: 1),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1
        )
        let projects = [snapshot, repository]
        let observed = ProjectRepositories.rows(snapshot: snapshot, projects: projects)
        XCTAssertEqual(observed.last?.kind, .workspaceObservation)
        XCTAssertEqual(observed.last?.projectId, "repo", "repository navigation remains available")
        XCTAssertTrue(ProjectRepositories.detail(observed[1]).contains(L("Observed in workspace Tasks")))
        XCTAssertEqual(ProjectRepositories.rows(snapshot: repository, projects: projects).map(\.kind), [.own])
        let model = AppModel()
        model.meshSnapshots = [snapshot.projectId: snapshot, repository.projectId: repository]
        RenderProbe.render(NavigationView {
            List { ProjectRepositoriesSection(snapshot: snapshot, model: model) }
        })
    }
}
