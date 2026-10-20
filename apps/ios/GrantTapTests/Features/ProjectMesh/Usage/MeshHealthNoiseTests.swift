import XCTest
import Combine
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

    func testHealthCountsCompletePartialUnavailableAndMissingSeparately() {
        var partial = graph("partial")
        partial.analysisStatus = "INCOMPLETE"
        let value = mesh([graph("repo"), partial,
                          graph("broken", unavailable: "ENGINE_ADMISSION_UNAVAILABLE")], at: 1,
                         bindings: ["repo", "partial", "broken", "missing"].map { binding($0, revision: "head") })
        let health = ProjectHealthPresentation(snapshot: value, connections: [])
        XCTAssertEqual(health.repositories.count, 4)
        XCTAssertEqual(health.readyCount, 1, "a partial report is inspectable, but is not complete")
        XCTAssertEqual(health.attentionCount, 3)
        XCTAssertEqual(health.repositories.filter(\.usable).count, 2)
        XCTAssertNil(health.repositories.first { $0.id == "missing" }?.report)
    }

    func testHealthDistinguishesForksAndRefreshesCachedFailures() {
        let repositories = ["repo", "github.com/one/app", "github.com/two/app"]
        let value = mesh(repositories.map { graph($0, unavailable: "REPOSITORY_NOT_BOUND") }, at: 1,
                         bindings: repositories.map { binding($0, revision: "head") })
        let cache = ProjectHealthPresentationCache()
        let initial = cache.value(for: value, connections: [])
        XCTAssertEqual(initial.repositories.filter { $0.disambiguation != nil }.count, 2)
        XCTAssertEqual(initial.readyCount, 0)
        var repaired = value
        repaired.repositoryGraphs = repositories.map { graph($0) }
        let fresh = cache.value(for: repaired, connections: [])
        XCTAssertEqual(fresh.readyCount, 3, "a received successful report replaces its cached failure")
        XCTAssertEqual(cache.value(for: repaired, connections: []), fresh)
        XCTAssertTrue(fresh.repositories.allSatisfy { $0.report?.analysisErrorCode == nil })
    }

    func testHealthKeepsOldArchitectureInspectableWithoutCallingItCurrent() {
        let value = mesh([graph("repo")], at: 1, bindings: [binding("repo", revision: "new-head")])
        let health = ProjectHealthPresentation(snapshot: value, connections: [])
        XCTAssertEqual(health.readyCount, 0)
        XCTAssertTrue(health.needsAnalysis)
        XCTAssertTrue(health.repositories[0].usable)
        XCTAssertTrue(health.repositories[0].stale)
        XCTAssertEqual(health.repositories[0].report?.revision, "head")
        let truncated = ProjectRepositoryGraph(projectId: "p", repositoryId: "repo", revision: "head",
            weavatrixVersion: "2.17.4", analysisStatus: "COMPLETE", nodes: [], relations: [],
            totalNodes: 3, totalRelations: 0, truncated: true)
        let partial = ProjectHealthPresentation(snapshot: mesh([truncated], at: 2,
            bindings: [binding("repo", revision: "head")]), connections: [])
        XCTAssertEqual(partial.readyCount, 0)
        XCTAssertTrue(partial.repositories[0].usable)
    }
    @MainActor
    func testTimestampOnlyAttentionUpdatesRemainDurableWithoutInvalidatingTheUI() {
        let model = AppModel()
        var updates = 0
        let observation = model.objectWillChange.sink { updates += 1 }
        defer { observation.cancel() }
        model.meshAttentionStates["scroll-fixture"] = .init(status: .acknowledged, createdAt: 1, updatedAt: 1)
        let first = updates
        model.meshAttentionStates["scroll-fixture"] = .init(status: .acknowledged, createdAt: 1, updatedAt: 2)
        XCTAssertEqual(updates, first)
        XCTAssertEqual(model.meshAttentionStates["scroll-fixture"]?.updatedAt, 2)
        model.meshAttentionStates["scroll-fixture"] = .init(status: .answered, createdAt: 1, updatedAt: 3)
        XCTAssertGreaterThan(updates, first, "a human decision must update its visible state")
        let answered = updates
        model.meshAttentionStates["scroll-fixture"] = .init(status: .snoozed, snoozedUntil: 10, updatedAt: 4)
        XCTAssertGreaterThan(updates, answered)
        let snoozed = updates
        model.meshAttentionStates["scroll-fixture"] = .init(status: .snoozed, snoozedUntil: 20, updatedAt: 5)
        XCTAssertGreaterThan(updates, snoozed, "a changed reminder time is visible")
        model.meshAttentionStates.removeValue(forKey: "scroll-fixture")
        XCTAssertNil(model.meshAttentionStates["scroll-fixture"])
    }

}
