import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class RepositoryFactsTests: XCTestCase {
    private let local = "local:/fixture/app"
    private let remote = "github.com/team/app"

    private func mesh(_ id: String = "source", canonical: String? = nil) -> ProjectMeshSnapshot {
        .init(type: "mesh.snapshot", sessionId: id, projectId: id,
            project: .init(projectId: id, name: id, canonicalRepositoryId: canonical ?? local, createdAt: 1),
            tasks: [.init(taskId: "stable", projectId: id, title: "Unrelated title", goal: "", state: "working",
                ownerSessionId: "native", createdAt: 1, updatedAt: 2)],
            executions: [.init(taskId: "stable", sessionId: "native", provider: "codex", computerId: "mac",
                workspace: "/fixture", repositoryId: local, branch: "feature", startedAt: 1)],
            claims: [], dependencies: [], events: [], generatedAt: 2)
    }

    private func report(endpoint: String = "mac", identity: String? = nil, status: String = "ready",
                        time: Double = 2) -> ProjectRepositoryDetails {
        .init(projectId: "source", repositoryId: local, canonicalRepositoryId: identity ?? remote,
            endpointId: endpoint, status: status, branch: "feature", revision: String(repeating: "a", count: 40),
            dirty: true, commitCount: 1,
            commits: [.init(sha: String(repeating: "a", count: 40), subject: "Verified commit",
                            author: "Fixture author", committedAt: 1)],
            contributors: [.init(name: "Fixture author", commits: 1)], contributorCount: 1, observedAt: time)
    }

    private func catalog(_ values: [ProjectMeshSnapshot]) -> [RepositoryCatalog.Entry] {
        let rows = ProjectsCatalog.rows(snapshots: values, sessions: [], preferences: [:], memberLinks: [], rooms: [:])
        return RepositoryCatalog.make(rows: rows, snapshots: Dictionary(uniqueKeysWithValues:
            values.map { ($0.projectId, $0) }), sessions: [])
    }

    func testProvenLocalAndRemoteIdentitiesProduceOneRepositoryAndOneTask() throws {
        var value = mesh()
        value.repositoryDetails = [report()]
        value.bindings = [.init(bindingId: "remote", projectId: "source", endpointId: "mac",
            repositoryId: remote, displayName: "app", available: true)]
        let entries = catalog([value])
        XCTAssertEqual(entries.map(\.id), [remote])
        XCTAssertEqual(entries[0].memberships.count, 1)
        XCTAssertEqual(entries[0].memberships[0].tasks.map(\.id), ["stable"])
        XCTAssertEqual(RepositoryActivity.working(entries[0]), 1)
        XCTAssertTrue(RepositoryActivity.summary(entries[0]).contains("feature"))
    }

    func testNewestUnavailableOrConflictingIdentityNeverJoinsRepositories() {
        var value = mesh()
        value.repositoryDetails = [report(), report(status: "not_git", time: 3)]
        XCTAssertEqual(RepositoryIdentityIndex.canonical(local, snapshots: [value]), local)
        value.repositoryDetails = [report(), report(endpoint: "other", identity: "github.com/team/fork")]
        XCTAssertEqual(RepositoryIdentityIndex.canonical(local, snapshots: [value]), local)
        value.repositoryDetails = [report()]
        XCTAssertEqual(RepositoryIdentityIndex.canonical(local, snapshots: [value]), remote)
        XCTAssertEqual(RepositoryIdentityIndex.canonical("unknown", snapshots: [value]), "unknown")
    }

    func testLocalAndRemoteReportsOfOneCheckoutDoNotCreateAmbiguousPlacement() throws {
        var source = mesh(canonical: "github.com/team/original")
        source.repositoryDetails = [report()]
        source.executions.append(.init(taskId: "stable", sessionId: "native", provider: "codex",
            computerId: "mac", workspace: "/fixture", repositoryId: remote, startedAt: 1))
        var target = mesh("target", canonical: remote)
        target.tasks = []; target.executions = []
        XCTAssertEqual(MeshTaskPlacement.make(snapshots: [source, target], sessions: []).first?.projectId, "target")
        let model = AppModel()
        model.meshSnapshots = [source.projectId: source, target.projectId: target]
        XCTAssertEqual(model.repositoryPlacedTasks(projectId: "target").map(\.task.taskId), ["stable"])
        XCTAssertTrue(model.repositoryPlacedTasks(projectId: "source").isEmpty)
        model.setProjectHidden("target", true)
        XCTAssertEqual(model.repositoryPlacedTasks(projectId: "source").map(\.task.taskId), ["stable"])
    }

    func testLatestReportsSurvivePartialRefreshAndEndedExecutionIsNotActive() {
        let newer = report(time: 10), older = report(time: 1)
        XCTAssertEqual(ProjectRepositoryDetails.merging([newer], [older]), [newer])
        XCTAssertEqual(ProjectRepositoryDetails.merging([newer], nil), [newer])
        XCTAssertNil(ProjectRepositoryDetails.merging(nil, []))
        var value = mesh()
        value.executions[0].endedAt = 3
        XCTAssertEqual(RepositoryActivity.working(catalog([value])[0]), 0)
        value.executions[0].repositoryId = remote
        let entries = catalog([value])
        XCTAssertEqual(RepositoryActivity.working(entries.first { $0.id == local }!), 0)
    }

    func testGitDetailsRenderReadyEmptyUnavailableAndUnknownWithoutChangingDurableScope() {
        let model = AppModel()
        var value = mesh()
        for reports in [nil, [report()], [report(status: "not_git")], [report(status: "unavailable")],
                        [.init(projectId: "source", repositoryId: local, endpointId: "mac", status: "ready", observedAt: 3)]] {
            value.repositoryDetails = reports
            model.meshSnapshots = [value.projectId: value]
            let entry = catalog([value])[0]
            RenderProbe.render(List { RepositoryGitSections(entry: entry, model: model) })
            RenderProbe.render(NavigationView { RepositoryCatalogDetailView(repositoryId: local, model: model) })
            XCTAssertEqual(model.meshSnapshots[value.projectId]?.tasks[0].projectId, "source")
        }
    }
}
