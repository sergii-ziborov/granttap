import XCTest
@testable import GrantTap

/// Mesh Health shows what a person can act on: repositories and their real
/// Graph state, in words, not raw codes or folders that were never repositories.
final class MeshHealthNoiseTests: XCTestCase {
    private func graph(_ repositoryId: String, unavailable code: String? = nil) -> ProjectRepositoryGraph {
        var report = ProjectRepositoryGraph(projectId: "p", repositoryId: repositoryId,
            revision: code == nil ? "head" : "unverified", weavatrixVersion: code == nil ? "2.17.4" : "unknown",
            analysisStatus: code == nil ? "COMPLETE" : "UNAVAILABLE", nodes: [], relations: [],
            totalNodes: code == nil ? 3 : 0, totalRelations: 0, truncated: false)
        report.analysisErrorCode = code
        return report
    }

    private func mesh(_ graphs: [ProjectRepositoryGraph]?, at generatedAt: Double,
                      bindings: [ProjectBindingSummary]) -> ProjectMeshSnapshot {
        ProjectMeshSnapshot(type: "mesh.snapshot", sessionId: "p", projectId: "p",
            project: ProjectMeshProject(projectId: "p", name: "Fixture", canonicalRepositoryId: "repo", createdAt: 1),
            bindings: bindings, repositoryGraphs: graphs, tasks: [], executions: [], claims: [],
            dependencies: [], events: [], generatedAt: generatedAt)
    }

    private func binding(_ repositoryId: String, revision: String?) -> ProjectBindingSummary {
        .init(bindingId: repositoryId, projectId: "p", endpointId: "mac", repositoryId: repositoryId,
              displayName: repositoryId, available: true, revision: revision)
    }

    func testAPlainFolderIsNotListedAsARepositoryWithoutAnalysis() {
        let plain = "local:/Users/fixture/dev"
        let value = mesh([graph("repo")], at: 1, bindings: [binding("repo", revision: "head"),
                                                            binding(plain, revision: nil)])
        XCTAssertEqual(ProjectHealthDiagnostics.graphRepositoryIds(value), ["repo"])
        var reported = value
        reported.repositoryGraphs?.append(graph(plain, unavailable: "REPOSITORY_NOT_LOCAL"))
        XCTAssertEqual(ProjectHealthDiagnostics.graphRepositoryIds(reported).count, 2,
                       "a folder the computer still reports about stays visible")
    }

    func testUnavailableGraphsAreExplainedInWordsNotCodes() {
        for code in ["ENGINE_ADMISSION_UNAVAILABLE", "REPOSITORY_IDENTITY_MISMATCH",
                     "REPOSITORY_IDENTITY_UNVERIFIED", "REPOSITORY_NOT_BOUND", nil] {
            let reason = ProjectRepositoryGraph.unavailableReason(code)
            XCTAssertFalse(reason.isEmpty)
            if let code { XCTAssertFalse(reason.contains(code), code) }
        }
        XCTAssertNotEqual(ProjectRepositoryGraph.unavailableReason("ENGINE_ADMISSION_UNAVAILABLE"),
                          ProjectRepositoryGraph.unavailableReason(nil))
    }

    func testANewerSnapshotClearsAFailureItNoLongerReports() {
        let old = mesh([graph("repo"), graph("local:/Users/fixture/dev", unavailable: "REPOSITORY_IDENTITY_UNVERIFIED")],
                       at: 1, bindings: [binding("repo", revision: "head")])
        let newer = mesh([graph("repo")], at: 2, bindings: [binding("repo", revision: "head")])
        let merged = ProjectMeshLogic.merged(current: old, incoming: newer, nowMs: 3)
        XCTAssertEqual(merged.repositoryGraphs?.map(\.repositoryId), ["repo"])
        let other = mesh([graph("other-repo")], at: 3, bindings: [binding("repo", revision: "head")])
        XCTAssertEqual(Set(ProjectMeshLogic.merged(current: newer, incoming: other, nowMs: 4)
            .repositoryGraphs?.map(\.repositoryId) ?? []), ["repo", "other-repo"],
            "a working graph another computer reported is kept")
        let stale = ProjectMeshLogic.merged(current: newer, incoming: old, nowMs: 4)
        XCTAssertEqual(stale.repositoryGraphs?.map(\.repositoryId), ["repo"],
                       "an older snapshot cannot bring a cleared failure back")
        let base = mesh(nil, at: 5, bindings: [binding("repo", revision: "head")])
        XCTAssertEqual(ProjectMeshLogic.merged(current: old, incoming: base, nowMs: 6).repositoryGraphs?.count, 2,
                       "a snapshot that carries no graphs says nothing about them")
    }
}
