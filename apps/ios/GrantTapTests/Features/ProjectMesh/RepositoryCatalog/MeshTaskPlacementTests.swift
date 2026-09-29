import XCTest
@testable import GrantTap

final class MeshTaskPlacementTests: XCTestCase {
    private func mesh(_ id: String, repo: String, ownerRepo: String? = nil) -> ProjectMeshSnapshot {
        let task = ProjectMeshTask(taskId: "stable", projectId: id, title: "Same title", goal: "",
            state: "working", ownerSessionId: "native", createdAt: 1, updatedAt: 2)
        let execution = ExecutionSessionLink(taskId: "stable", sessionId: "native", provider: "codex",
            computerId: "mac", workspace: "/dev", repositoryId: ownerRepo, branch: "main", startedAt: 1)
        return .init(type: "mesh.snapshot", sessionId: id, projectId: id,
            project: .init(projectId: id, name: id, canonicalRepositoryId: repo, createdAt: 1),
            tasks: ownerRepo == nil ? [] : [task], executions: ownerRepo == nil ? [] : [execution],
            claims: [], dependencies: [], events: [], generatedAt: 2)
    }

    func testTaskStartedInWrongMeshIsPresentedInUniqueRepositoryMeshWithOriginalRouteIntact() throws {
        let source = mesh("wrong", repo: "github.com/team/old", ownerRepo: "github.com/team/app")
        let target = mesh("correct", repo: "github.com/team/app")
        let placed = try XCTUnwrap(MeshTaskPlacement.make(snapshots: [source, target], sessions: []).first)
        XCTAssertEqual(placed.projectId, "correct")
        XCTAssertEqual(placed.sourceProjectId, "wrong")
        XCTAssertEqual(placed.row.task.projectId, "wrong")
        XCTAssertEqual(placed.row.task.taskId, "stable")
        XCTAssertEqual(source.tasks.first?.projectId, "wrong")
    }

    func testAmbiguousTargetAndMissingOwnerEvidenceStayInSourceMesh() {
        var source = mesh("wrong", repo: "github.com/team/old", ownerRepo: "github.com/team/app")
        let a = mesh("a", repo: "github.com/team/app"), b = mesh("b", repo: "github.com/team/app")
        XCTAssertEqual(MeshTaskPlacement.make(snapshots: [source, a, b], sessions: []).first?.projectId, "wrong")
        source.tasks[0].ownerSessionId = nil
        XCTAssertEqual(MeshTaskPlacement.make(snapshots: [source, a], sessions: []).first?.projectId, "wrong")
    }

    func testPlacementRecomputesWhenExecutionRepositoryChangesWithoutGuessingFromTitle() {
        var source = mesh("wrong", repo: "github.com/team/old", ownerRepo: "github.com/team/app")
        let target = mesh("correct", repo: "github.com/team/app")
        XCTAssertEqual(MeshTaskPlacement.make(snapshots: [target, source], sessions: []).first?.projectId, "correct")
        source.executions[0].repositoryId = "github.com/team/old"
        source.tasks[0].title = "Work on github.com/team/app"
        XCTAssertEqual(MeshTaskPlacement.make(snapshots: [source, target], sessions: []).first?.projectId, "wrong")
    }
}
