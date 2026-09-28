import XCTest
@testable import GrantTap

final class ProjectSolutionGroupsTests: XCTestCase {
    func testWorkspaceObservationsDoNotJoinUnrelatedRepositoryMeshes() {
        var workspace = snapshot("workspace", repository: "local:/Users/me/dev")
        workspace.bindings = ["repo:a", "repo:b"].map { repository in
            ProjectBindingSummary(
                bindingId: repository, projectId: "workspace", endpointId: "mac",
                repositoryId: repository, displayName: repository, available: true,
                revision: "verified-head"
            )
        }
        let projects = [workspace, snapshot("a", repository: "repo:a"), snapshot("b", repository: "repo:b")]
        let grouped = ProjectSolutionGroups.make(
            rows: projects.map { row($0.projectId, name: $0.projectId) },
            snapshots: Dictionary(uniqueKeysWithValues: projects.map { ($0.projectId, $0) })
        )
        XCTAssertTrue(grouped.linked.isEmpty, "a workspace is not a repository relationship")
        XCTAssertEqual(Set(grouped.ungrouped.map(\.projectId)), ["workspace", "a", "b"])
    }

    private func row(_ id: String, name: String) -> ProjectListRow {
        ProjectListRow(projectId: id, name: name, repositoryLeaf: name,
                       computers: 1, openTasks: 1, working: 0, needsYou: 0,
                       members: 0, holdsKey: true, hidden: false, lastActiveAt: 1)
    }

    private func snapshot(_ id: String, repository: String) -> ProjectMeshSnapshot {
        ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: id, projectId: id,
            project: .init(projectId: id, name: "same name", repositoryRoot: nil,
                           canonicalRepositoryId: repository, createdAt: 1),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1
        )
    }

    func testVerifiedCrossRepositoryEvidenceGroupsWithoutMergingProjects() {
        var outer = snapshot("outer", repository: "repo/granttap")
        let inner = snapshot("inner", repository: "repo/granttap-internal")
        outer.backbone = ProjectBackbone(projectId: "outer", nodes: [
            .init(kind: "repository", identity: "repo/granttap", displayName: "granttap"),
            .init(kind: "repository", identity: "repo/granttap-internal", displayName: "internal"),
            .init(kind: "package", identity: "app", displayName: "App"),
            .init(kind: "package", identity: "engine", displayName: "Engine"),
        ], relations: [
            .init(source: "repo/granttap", target: "app", relation: "owns", evidenceCount: 1),
            .init(source: "repo/granttap-internal", target: "engine", relation: "owns", evidenceCount: 1),
            .init(source: "app", target: "engine", relation: "uses", evidenceCount: 2),
        ], pendingCandidateCount: 0)
        let result = ProjectSolutionGroups.make(
            rows: [row("outer", name: "granttap"), row("inner", name: "internal")],
            snapshots: ["outer": outer, "inner": inner]
        )
        XCTAssertEqual(result.solutions.count, 1)
        XCTAssertEqual(Set(result.solutions[0].rows.map(\.projectId)), ["outer", "inner"])
        XCTAssertTrue(result.ungrouped.isEmpty)
    }

    func testBindingCreatesLinkedGroupButNotWeavatrixSolution() {
        var outer = snapshot("outer", repository: "repo/a")
        let inner = snapshot("inner", repository: "repo/b")
        outer.bindings = [.init(bindingId: "binding", projectId: "outer", endpointId: "mac",
                                repositoryId: "repo/b", displayName: "same", available: true)]
        outer.backbone = ProjectBackbone(projectId: "outer", nodes: [
            .init(kind: "repository", identity: "repo/a", displayName: "same"),
            .init(kind: "repository", identity: "repo/b", displayName: "same"),
        ], relations: [.init(source: "repo/a", target: "repo/b", relation: "uses", evidenceCount: 0)],
                                         pendingCandidateCount: 1)
        let result = ProjectSolutionGroups.make(
            rows: [row("outer", name: "same"), row("inner", name: "same")],
            snapshots: ["outer": outer, "inner": inner]
        )
        XCTAssertTrue(result.solutions.isEmpty)
        XCTAssertEqual(result.linked.map { Set($0.rows.map(\.projectId)) }, [["outer", "inner"]])
        XCTAssertTrue(result.ungrouped.isEmpty)
    }

    func testSameNameWithoutBindingOrEvidenceStaysSeparate() {
        let first = snapshot("first", repository: "repo/a")
        let second = snapshot("second", repository: "repo/b")
        let result = ProjectSolutionGroups.make(
            rows: [row("first", name: "same"), row("second", name: "same")],
            snapshots: ["first": first, "second": second]
        )
        XCTAssertTrue(result.solutions.isEmpty)
        XCTAssertTrue(result.linked.isEmpty)
        XCTAssertEqual(result.ungrouped.count, 2)
    }

    func testVerifiedRepositoryOwnershipGroupsNestedMeshWithoutJoiningItsScope() {
        var parent = snapshot("parent", repository: "repo/main")
        let child = snapshot("child", repository: "repo/module")
        parent.backbone = ProjectBackbone(projectId: "parent", nodes: [
            .init(kind: "repository", identity: "repo/main", displayName: "main"),
            .init(kind: "repository", identity: "repo/module", displayName: "module"),
        ], relations: [
            .init(source: "repo/main", target: "repo/module", relation: "owns", evidenceCount: 1),
        ], pendingCandidateCount: 0)
        let result = ProjectSolutionGroups.make(
            rows: [row("parent", name: "main"), row("child", name: "module")],
            snapshots: ["parent": parent, "child": child]
        )
        XCTAssertEqual(result.solutions.map { Set($0.rows.map(\.projectId)) }, [["parent", "child"]])
        XCTAssertEqual(parent.projectId, "parent")
        XCTAssertEqual(child.projectId, "child")
    }

    func testDeepOwnershipChainKeepsCrossRepositoryRelationVisible() {
        var outer = snapshot("outer", repository: "repo/a")
        let inner = snapshot("inner", repository: "repo/b")
        let packages = (1...6).map { "layer\($0)" }
        let ownership = (0..<packages.count).reversed().map { index in
            ProjectBackboneRelation(
                source: index == 0 ? "repo/a" : packages[index - 1],
                target: packages[index], relation: "owns", evidenceCount: 1
            )
        }
        outer.backbone = ProjectBackbone(projectId: "outer", nodes: [
            .init(kind: "repository", identity: "repo/a", displayName: "A"),
            .init(kind: "repository", identity: "repo/b", displayName: "B"),
            .init(kind: "package", identity: "component-b", displayName: "B component"),
        ] + packages.map { .init(kind: "package", identity: $0, displayName: $0) },
        relations: ownership + [
            .init(source: "repo/b", target: "component-b", relation: "owns", evidenceCount: 1),
            .init(source: "layer6", target: "component-b", relation: "uses", evidenceCount: 1),
        ], pendingCandidateCount: 0)
        let result = ProjectSolutionGroups.make(
            rows: [row("outer", name: "A"), row("inner", name: "B")],
            snapshots: ["outer": outer, "inner": inner]
        )
        XCTAssertEqual(result.solutions.count, 1)
    }

    func testAmbiguousOwnershipCannotCreateSolutionGroup() {
        var first = snapshot("first", repository: "repo/a")
        let second = snapshot("second", repository: "repo/b")
        let third = snapshot("third", repository: "repo/c")
        first.backbone = ProjectBackbone(projectId: "first", nodes: [
            .init(kind: "repository", identity: "repo/a", displayName: "A"),
            .init(kind: "repository", identity: "repo/b", displayName: "B"),
            .init(kind: "repository", identity: "repo/c", displayName: "C"),
            .init(kind: "package", identity: "shared", displayName: "Shared"),
            .init(kind: "package", identity: "component-c", displayName: "C component"),
        ], relations: [
            .init(source: "repo/a", target: "shared", relation: "owns", evidenceCount: 1),
            .init(source: "repo/b", target: "shared", relation: "owns", evidenceCount: 1),
            .init(source: "repo/c", target: "component-c", relation: "owns", evidenceCount: 1),
            .init(source: "shared", target: "component-c", relation: "uses", evidenceCount: 1),
        ], pendingCandidateCount: 0)
        let result = ProjectSolutionGroups.make(
            rows: [row("first", name: "A"), row("second", name: "B"), row("third", name: "C")],
            snapshots: ["first": first, "second": second, "third": third]
        )
        XCTAssertTrue(result.solutions.isEmpty)
    }

    func testExecutionRepositoryLinksMeshWithoutABindingOrGraph() {
        var outer = snapshot("outer", repository: "repo/granttap")
        let inner = snapshot("inner", repository: "repo/internal")
        outer.tasks = [.init(taskId: "task", projectId: "outer", title: "Task", goal: "",
                             state: "completed", ownerSessionId: nil, createdAt: 1, updatedAt: 2)]
        outer.executions = [.init(taskId: "task", sessionId: "native", provider: "codex",
                                  computerId: "mac", workspace: "/checkout", repositoryId: "repo/internal",
                                  branch: nil, worktree: nil, startedAt: 1, endedAt: 2)]
        let result = ProjectSolutionGroups.make(
            rows: [row("outer", name: "granttap"), row("inner", name: "internal")],
            snapshots: ["outer": outer, "inner": inner]
        )
        XCTAssertEqual(result.linked.map { Set($0.rows.map(\.projectId)) }, [["outer", "inner"]])
        XCTAssertTrue(result.solutions.isEmpty)
        XCTAssertTrue(result.ungrouped.isEmpty)
        XCTAssertEqual(outer.projectId, "outer")
        XCTAssertEqual(inner.projectId, "inner")
    }

    func testSharedRepositoryLinksScopesWithDifferentCanonicalRepositories() {
        var first = snapshot("first", repository: "repo/a")
        var second = snapshot("second", repository: "repo/b")
        first.bindings = [.init(bindingId: "a", projectId: "first", endpointId: "mac-a",
                                repositoryId: "repo/shared", displayName: "Shared", available: true)]
        second.bindings = [.init(bindingId: "b", projectId: "second", endpointId: "mac-b",
                                 repositoryId: "repo/shared", displayName: "Other name", available: false)]
        let result = ProjectSolutionGroups.make(
            rows: [row("first", name: "A"), row("second", name: "B")],
            snapshots: ["first": first, "second": second]
        )
        XCTAssertEqual(result.linked.map { Set($0.rows.map(\.projectId)) }, [["first", "second"]])
        XCTAssertTrue(result.ungrouped.isEmpty)
    }

    func testSameRepositoryScopesGroupWhileDifferentRepositoriesStaySeparate() {
        let snapshots = ["a": snapshot("a", repository: "repo/shared"),
                         "b": snapshot("b", repository: "repo/shared"),
                         "c": snapshot("c", repository: "repo/unrelated")]
        let result = ProjectSolutionGroups.make(
            rows: [row("a", name: "One"), row("b", name: "Two"), row("c", name: "One")],
            snapshots: snapshots
        )
        XCTAssertEqual(result.linked.map { Set($0.rows.map(\.projectId)) }, [["a", "b"]])
        XCTAssertEqual(result.ungrouped.map(\.projectId), ["c"])
    }

    func testForeignBindingsAndExecutionsCannotConnectVisibleMesh() {
        var first = snapshot("first", repository: "repo/a")
        first.bindings = [.init(bindingId: "foreign", projectId: "someone-else", endpointId: "mac",
                                repositoryId: "repo/b", displayName: "B", available: true)]
        first.executions = [.init(taskId: "foreign-task", sessionId: "native", provider: "codex",
                                  computerId: "mac", workspace: "/checkout", repositoryId: "repo/b",
                                  branch: nil, worktree: nil, startedAt: 1, endedAt: nil)]
        let result = ProjectSolutionGroups.make(
            rows: [row("first", name: "A"), row("second", name: "B")],
            snapshots: ["first": first, "second": snapshot("second", repository: "repo/b")]
        )
        XCTAssertTrue(result.linked.isEmpty)
        XCTAssertEqual(result.ungrouped.count, 2)
    }
}
