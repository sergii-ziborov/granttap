import XCTest
@testable import GrantTap

@MainActor
final class RepositoryCatalogTests: XCTestCase {
    private let a = "github.com/owner-a/api"
    private let b = "github.com/owner-b/api"

    private func snapshot(_ id: String, repository: String, tasks: [ProjectMeshTask] = [],
                          executions: [ExecutionSessionLink] = []) -> ProjectMeshSnapshot {
        .init(type: "mesh.snapshot", sessionId: id, projectId: id,
              project: .init(projectId: id, name: "Unhelpful name", canonicalRepositoryId: repository, createdAt: 1),
              tasks: tasks, executions: executions, claims: [], dependencies: [], events: [], generatedAt: 1)
    }

    private func task(_ id: String, project: String, owner: String? = nil) -> ProjectMeshTask {
        .init(taskId: id, projectId: project, title: "Continue", goal: "", state: "working",
              ownerSessionId: owner, createdAt: 1, updatedAt: 2)
    }

    private func execution(_ task: String, session: String, repository: String?, ended: Double? = nil)
        -> ExecutionSessionLink {
        .init(taskId: task, sessionId: session, provider: "codex", computerId: "mac",
              workspace: "/dev", repositoryId: repository, branch: "main", startedAt: 1, endedAt: ended)
    }

    private func catalog(_ snapshots: [ProjectMeshSnapshot], hidden: Set<String> = []) -> [RepositoryCatalog.Entry] {
        let preferences = Dictionary(uniqueKeysWithValues: hidden.map { ($0, ProjectPreference(hidden: true)) })
        let rows = ProjectsCatalog.rows(snapshots: snapshots, sessions: [], preferences: preferences,
                                        memberLinks: [], rooms: [:])
        return RepositoryCatalog.make(rows: rows, snapshots: Dictionary(uniqueKeysWithValues:
            snapshots.map { ($0.projectId, $0) }), sessions: [])
    }

    func testSameIdentityHasAllMeshScopesAndSameLeafNamesStaySeparate() throws {
        let entries = catalog([snapshot("one", repository: a), snapshot("two", repository: a),
                               snapshot("three", repository: b)])
        XCTAssertEqual(entries.map(\.id), [a, b])
        XCTAssertEqual(try XCTUnwrap(entries.first).memberships.map(\.projectId), ["one", "two"])
        XCTAssertTrue(entries.allSatisfy(\.isGit))
    }

    func testWorkspaceTasksAreIndexedByExecutionWithoutMergingMeshesOrTrustingTitles() throws {
        var workspace = snapshot("dev", repository: "local:/dev", tasks: [
            task("a", project: "dev", owner: "sa"), task("b", project: "dev", owner: "sb"),
            task("unknown", project: "dev")], executions: [
                execution("a", session: "sa", repository: a), execution("b", session: "sb", repository: b)])
        workspace.tasks[2].title = "Work on \(a)"
        let entries = catalog([workspace])
        XCTAssertEqual(entries.filter(\.isGit).map(\.id), [a, b])
        XCTAssertEqual(entries.first { $0.id == a }?.memberships.first?.tasks.map(\.id), ["a"])
        let unknown = try XCTUnwrap(entries.first { !$0.isGit }?.memberships.first?.tasks.first)
        XCTAssertEqual(unknown.id, "unknown")
        XCTAssertEqual(unknown.relation, .unassigned)
        XCTAssertEqual(workspace.tasks.map(\.projectId), ["dev", "dev", "dev"])
    }

    func testCurrentRepositoryAndEarlierExecutionRemainExplicitAfterHandoff() throws {
        var project = snapshot("mesh", repository: a, tasks: [task("stable", project: "mesh", owner: "new")],
            executions: [execution("stable", session: "old", repository: a, ended: 2),
                         execution("stable", session: "new", repository: b)])
        var entries = catalog([project])
        XCTAssertEqual(entries.first { $0.id == a }?.memberships.first?.tasks.first?.relation, .previous)
        XCTAssertEqual(entries.first { $0.id == b }?.memberships.first?.tasks.first?.relation, .current)
        project.tasks[0].ownerSessionId = "old"
        entries = catalog([project])
        XCTAssertEqual(entries.first { $0.id == a }?.memberships.first?.tasks.first?.relation, .current)
        XCTAssertEqual(entries.first { $0.id == b }?.memberships.first?.tasks.first?.relation, .previous)
    }

    func testMissingOwnerAndConflictingReportsNeverClaimCurrentRepository() {
        let project = snapshot("mesh", repository: a, tasks: [task("history", project: "mesh"),
            task("conflict", project: "mesh", owner: "same")], executions: [
                execution("history", session: "old", repository: b, ended: 2),
                execution("conflict", session: "same", repository: a),
                execution("conflict", session: "same", repository: b)])
        let refs = catalog([project]).first { $0.id == b }?.memberships.first?.tasks ?? []
        XCTAssertEqual(refs.first { $0.id == "history" }?.relation, .lastObserved)
        XCTAssertEqual(refs.first { $0.id == "conflict" }?.relation, .multiple)
    }

    func testForeignAndHiddenScopeRecordsAreExcludedWhileOfflineBindingsRemain() {
        var project = snapshot("mesh", repository: a)
        project.bindings = [
            .init(bindingId: "own", projectId: "mesh", endpointId: "offline", repositoryId: b,
                  displayName: "api", available: false),
            .init(bindingId: "foreign", projectId: "other", endpointId: "pc", repositoryId: "github.com/foreign/repo",
                  displayName: "foreign", available: true)]
        project.executions = [execution("foreign-task", session: "f", repository: "github.com/foreign/execution")]
        let entries = catalog([project, snapshot("hidden", repository: "github.com/private/hidden")], hidden: ["hidden"])
        XCTAssertEqual(entries.map(\.id), [a, b])
        XCTAssertEqual(entries.first { $0.id == b }?.memberships.first?.computers, ["offline"])
        XCTAssertEqual(entries.first { $0.id == b }?.memberships.first?.bound, true)
    }

    func testLocalGitEvidenceIsRetainedAndInputOrderingDoesNotAffectIndex() {
        var project = snapshot("mesh", repository: "local:/dev/api")
        project.bindings = [.init(bindingId: "git", projectId: "mesh", endpointId: "mac",
            repositoryId: "local:/dev/api", displayName: "API", available: false, revision: "head")]
        let snapshots = [project, snapshot("peer", repository: a)]
        XCTAssertTrue(catalog(snapshots).first { $0.id == "local:/dev/api" }?.isGit == true)
        XCTAssertEqual(catalog(snapshots).map(\.id), catalog(Array(snapshots.reversed())).map(\.id))
        XCTAssertTrue(catalog([]).isEmpty)
    }
}
