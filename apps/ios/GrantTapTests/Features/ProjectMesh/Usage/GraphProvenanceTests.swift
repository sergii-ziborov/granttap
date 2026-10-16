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

    func testFreshGitIdentityReplacesAStaleLocalAliasFailureWithoutRequestingAnotherBuild() {
        var value = mesh(status: "INCOMPLETE", sourceRevision: "git-head")
        let alias = "local:/fixture/checkout"
        value.bindings?.append(.init(bindingId: "old-local", projectId: "p", endpointId: "mac",
            repositoryId: alias, displayName: "Checkout", available: true, revision: "obsolete-head"))
        value.repositoryDetails = [.init(projectId: "p", repositoryId: alias, canonicalRepositoryId: "repo",
            endpointId: "mac", status: "ready", revision: "git-head", observedAt: 10)]
        value.repositoryGraphs?.append(.init(projectId: "p", repositoryId: alias, revision: "unverified",
            weavatrixVersion: "unknown", analysisStatus: "UNAVAILABLE",
            analysisErrorCode: "REPOSITORY_IDENTITY_MISMATCH", nodes: [], relations: [],
            totalNodes: 0, totalRelations: 0, truncated: false))
        XCTAssertEqual(ProjectInsightReports.reports(value).map(\.repositoryId), ["repo"])
        XCTAssertEqual(ProjectHealthDiagnostics.graphRepositoryIds(value), ["repo"])
        XCTAssertEqual(ProjectHealthDiagnostics.graphReport(for: alias, snapshot: value)?.repositoryId, "repo")
        XCTAssertFalse(ProjectInsightReports.needsAnalysis(value))
        value.repositoryDetails?.append(.init(projectId: "p", repositoryId: alias,
            endpointId: "mac", status: "not_git", observedAt: 11))
        XCTAssertEqual(ProjectInsightReports.reports(value).count, 2,
            "A newer failed identity check must keep the alias separate.")
        XCTAssertEqual(ProjectHealthDiagnostics.graphRepositoryIds(value).count, 2)
        XCTAssertEqual(ProjectHealthDiagnostics.graphReport(for: alias, snapshot: value)?.analysisStatus, "UNAVAILABLE")
        XCTAssertTrue(ProjectInsightReports.needsAnalysis(value))
    }

    func testAConfirmedLocalAliasCannotHideAChangedOrUnrelatedRemote() {
        var value = mesh(status: "COMPLETE", sourceRevision: "git-head")
        let fork = "github.com/other/fork"
        value.repositoryGraphs?.append(.init(projectId: "p", repositoryId: fork, revision: "unverified",
            weavatrixVersion: "unknown", analysisStatus: "UNAVAILABLE",
            analysisErrorCode: "REPOSITORY_IDENTITY_MISMATCH", nodes: [], relations: [],
            totalNodes: 0, totalRelations: 0, truncated: false))
        value.repositoryDetails = [.init(projectId: "p", repositoryId: "local:/fixture/checkout",
            canonicalRepositoryId: "repo", endpointId: "mac", status: "ready", observedAt: 10)]
        XCTAssertEqual(Set(ProjectInsightReports.reports(value).map(\.repositoryId)), ["repo", fork])
    }

    func testAnAliasWithoutAPublishedGitRevisionDoesNotCompareTheContentFingerprintToGitHead() {
        var value = mesh(status: "INCOMPLETE", sourceRevision: nil)
        value.bindings?[0].revision = nil
        value.repositoryDetails = [.init(projectId: "p", repositoryId: "repo", canonicalRepositoryId: "canonical",
            endpointId: "mac", status: "ready", revision: "git-head", observedAt: 10)]
        XCTAssertFalse(ProjectInsightReports.needsAnalysis(value))
    }
}
