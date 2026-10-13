import XCTest
@testable import GrantTap

final class GraphProvenanceTests: XCTestCase {
    private func mesh(status: String?, sourceRevision: String?) -> ProjectMeshSnapshot {
        let project = ProjectMeshProject(projectId: "p", name: "Fixture", canonicalRepositoryId: "repo", createdAt: 1)
        var graph = ProjectRepositoryGraph(projectId: "p", repositoryId: "repo", revision: "content-hash",
            weavatrixVersion: "2.17.4", analysisStatus: status, nodes: [], relations: [],
            totalNodes: 4, totalRelations: 0, truncated: false)
        graph.sourceRevision = sourceRevision
        return ProjectMeshSnapshot(type: "mesh.snapshot", sessionId: "p", projectId: "p", project: project,
            bindings: [.init(bindingId: "b", projectId: "p", endpointId: "mac", repositoryId: "repo",
                displayName: "Fixture", available: true, revision: "git-head")],
            repositoryGraphs: [graph], tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1)
    }

    func testContentFingerprintDoesNotTriggerAnotherBuildOfTheSameGitRevision() {
        XCTAssertFalse(ProjectInsightReports.needsAnalysis(mesh(status: "COMPLETE", sourceRevision: "git-head")))
        XCTAssertFalse(ProjectInsightReports.needsAnalysis(mesh(status: "INCOMPLETE", sourceRevision: "git-head")))
        XCTAssertTrue(ProjectInsightReports.needsAnalysis(mesh(status: "COMPLETE", sourceRevision: "old-head")))
    }

    func testLegacyPlaceholderDoesNotStopAutomaticAnalysisOrConfirmAnExplicitBuild() {
        var snapshot = mesh(status: nil, sourceRevision: "git-head")
        XCTAssertTrue(ProjectInsightReports.needsAnalysis(snapshot))
        XCTAssertFalse(ProjectInsightReports.hasEvidence(snapshot))
        let request = ProjectGraphRequest(createdAt: 1)
        snapshot.graphAnalysisRequestId = request.requestId
        XCTAssertEqual(request.receiving(snapshot).result, .failed)
    }

    func testFailedRepositoryLeavesSuccessfulRepositoriesVisibleAndMarksBuildPartial() {
        var snapshot = mesh(status: "COMPLETE", sourceRevision: "git-head")
        snapshot.repositoryGraphs?.append(.init(projectId: "p", repositoryId: "missing", revision: "unverified",
            weavatrixVersion: "unknown", analysisStatus: "UNAVAILABLE", nodes: [], relations: [],
            totalNodes: 0, totalRelations: 0, truncated: false))
        let request = ProjectGraphRequest(createdAt: 1)
        snapshot.graphAnalysisRequestId = request.requestId
        XCTAssertEqual(request.receiving(snapshot).result, .partial)
        XCTAssertFalse(request.receiving(snapshot).pending)
        XCTAssertTrue(ProjectInsightReports.hasEvidence(snapshot))
    }

    func testEncryptedMeshWireAcceptsTheBuildReceiptAndSourceRevision() throws {
        var snapshot = mesh(status: "COMPLETE", sourceRevision: "git-head")
        snapshot.graphAnalysisRequestId = "requested-build-receipt"
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertTrue(ProjectMeshWireValidator.validSnapshot(data),
            "An authenticated explicit build response must reach its waiting request")
        let decoded = try JSONDecoder().decode(ProjectMeshSnapshot.self, from: data)
        XCTAssertEqual(decoded.graphAnalysisRequestId, snapshot.graphAnalysisRequestId)
        XCTAssertEqual(decoded.repositoryGraphs?.first?.sourceRevision, "git-head")
    }
}
