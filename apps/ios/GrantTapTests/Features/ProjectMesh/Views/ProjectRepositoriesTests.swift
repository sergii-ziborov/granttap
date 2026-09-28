import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class ProjectRepositoriesTests: XCTestCase {
    private func project(_ id: String, name: String, repo: String) -> ProjectMeshProject {
        ProjectMeshProject(projectId: id, name: name, repositoryRoot: "/Users/me/dev/\(name)", canonicalRepositoryId: repo, createdAt: 1)
    }

    private func snapshot() -> ProjectMeshSnapshot {
        let app = project("p-app", name: "nodvox", repo: "github.com/sergii/nodvox")
        var snapshot = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "p-app", projectId: "p-app", project: app,
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1
        )
        snapshot.bindings = [
            ProjectBindingSummary(bindingId: "b1", projectId: "p-app", endpointId: "Mac.lan", repositoryId: "github.com/sergii/nodvox", displayName: "nodvox", available: true),
            ProjectBindingSummary(bindingId: "b2", projectId: "p-app", endpointId: "Air.local", repositoryId: "github.com/sergii/nodvox", displayName: "nodvox", available: false),
            ProjectBindingSummary(bindingId: "b3", projectId: "p-app", endpointId: "Mac.lan", repositoryId: "github.com/sergii/granttap-mcp", displayName: "granttap-mcp", available: true),
            ProjectBindingSummary(bindingId: "b4", projectId: "p-app", endpointId: "Mac.lan", repositoryId: "github.com/sergii/scratch", displayName: "scratch", available: true),
        ]
        snapshot.peers = [
            ProjectIntegrationPeer(projectId: "p-app", repositoryId: "github.com/sergii/nodvox", peer: "granttap-mcp", via: "protocol", relation: "runtime", updatedAt: 1),
            ProjectIntegrationPeer(projectId: "p-app", repositoryId: "github.com/sergii/nodvox", peer: "granttap-mcp", via: "protocol", relation: "runtime", updatedAt: 2),
            ProjectIntegrationPeer(projectId: "p-app", repositoryId: "github.com/sergii/nodvox", peer: "granttap-site", via: "release", relation: "site", updatedAt: 1),
        ]
        snapshot.executions = [
            ExecutionSessionLink(taskId: "t1", sessionId: "s1", provider: "claude", computerId: "Mac.lan", workspace: "/Users/me/dev/nodvox", repositoryId: "github.com/sergii/nodvox", branch: "main", startedAt: 1),
            ExecutionSessionLink(taskId: "t2", sessionId: "s2", provider: "claude", computerId: "Mac.lan", workspace: "/Users/me/dev/nodvox", repositoryId: "github.com/sergii/nodvox", branch: "feat/x", startedAt: 1),
            ExecutionSessionLink(taskId: "t3", sessionId: "s3", provider: "codex", computerId: "Mac.lan", workspace: "/Users/me/dev/granttap-mcp", repositoryId: "github.com/sergii/granttap-mcp", branch: "main", startedAt: 1, endedAt: 2),
            ExecutionSessionLink(taskId: "t4", sessionId: "s4", provider: "codex", computerId: "Mac.lan", workspace: "/Users/me/dev/other", repositoryId: "github.com/sergii/other", startedAt: 1),
        ]
        return snapshot
    }

    func testTheOwnRepositoryComesFirstThenTheMapThenWhatElseWasBound() {
        let mcp = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "p-mcp", projectId: "p-mcp",
            project: project("p-mcp", name: "granttap-mcp", repo: "github.com/sergii/granttap-mcp"),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1
        )
        let rows = ProjectRepositories.rows(snapshot: snapshot(), projects: [snapshot(), mcp])
        XCTAssertEqual(rows.map(\.name), ["nodvox", "granttap-mcp", "granttap-site", "other", "scratch"])
        XCTAssertEqual(rows[0].kind, .own)
        XCTAssertEqual(rows[0].computers.map(\.endpointId), ["Mac.lan", "Air.local"], "available first")
        XCTAssertEqual(rows[0].openTasks, 2)
        XCTAssertEqual(rows[0].branches, ["feat/x", "main"])
        XCTAssertNil(rows[0].projectId)
        XCTAssertEqual(rows[1].kind, .peer(via: "protocol", relation: "runtime", through: nil))
        XCTAssertEqual(rows[1].projectId, "p-mcp", "the peer is a Project on this phone")
        XCTAssertEqual(rows[1].computers.map(\.endpointId), ["Mac.lan"])
        XCTAssertEqual(rows[1].openTasks, 0, "its one execution has ended")
        XCTAssertEqual(rows[2].computers.count, 0)
        XCTAssertNil(rows[2].projectId)
        XCTAssertEqual(rows[3].kind, .seen)
        XCTAssertEqual(rows[3].openTasks, 1)
        XCTAssertEqual(rows[4].kind, .seen)
        XCTAssertEqual(ProjectRepositories.repositoryLeaf("github.com/x/y.git/"), "y")
        var mismatchedAlias = snapshot()
        mismatchedAlias.bindings?.append(ProjectBindingSummary(
            bindingId: "old-alias", projectId: "p-app", endpointId: "Mac.lan",
            repositoryId: "github.com/sergii/granttap", displayName: "nodvox", available: true
        ))
        XCTAssertEqual(ProjectOtherSide.displayName(
            of: "github.com/sergii/granttap", in: mismatchedAlias
        ), "granttap")
        XCTAssertTrue(ProjectRepositories.detail(rows[0]).contains("Mac.lan"))
        XCTAssertTrue(ProjectRepositories.detail(rows[0]).contains(L("offline")))
        XCTAssertTrue(ProjectRepositories.detail(rows[2]).contains(L("not bound on any computer")))
        XCTAssertTrue(ProjectRepositories.detail(rows[3]).contains(L("bound here, not in the map")))
        XCTAssertEqual(rows[0], rows[0])
        XCTAssertNotEqual(rows[0], rows[1])
    }

    func testNonGitProjectRootIsShownAsWorkspaceWithBoundCheckout() {
        var project = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "p-app", projectId: "p-app",
            project: self.project("p-app", name: "dev", repo: "local:/Users/me/dev"),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1
        )
        project.bindings = [
            ProjectBindingSummary(bindingId: "workspace", projectId: "p-app", endpointId: "Mac.lan",
                                  repositoryId: "local:/Users/me/dev", displayName: "dev", available: true),
            ProjectBindingSummary(bindingId: "lad", projectId: "p-app", endpointId: "Mac.lan",
                                  repositoryId: "github.com/owner/lad", displayName: "Lad",
                                  available: true, revision: String(repeating: "a", count: 40)),
        ]
        project.peers = nil
        let rows = ProjectRepositories.rows(snapshot: project, projects: [project])
        XCTAssertEqual(rows.first?.kind, .workspace)
        XCTAssertTrue(ProjectRepositories.detail(rows[0]).contains("no Git repository confirmed"))
        XCTAssertEqual(rows.first { $0.id == "github.com/owner/lad" }?.kind, .workspaceObservation)
    }

    func testSharedBindingIsVisibleFromBothSeparateProjectScopes() throws {
        var parent = snapshot()
        parent.peers = nil
        let child = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "p-mcp", projectId: "p-mcp",
            project: project("p-mcp", name: "granttap-mcp", repo: "github.com/sergii/granttap-mcp"),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1
        )
        let projects = [parent, child]
        let fromParent = ProjectRepositories.rows(snapshot: parent, projects: projects)
        let fromChild = ProjectRepositories.rows(snapshot: child, projects: projects)
        XCTAssertEqual(fromParent.first { $0.name == "granttap-mcp" }?.projectId, "p-mcp")
        XCTAssertEqual(fromParent.first { $0.name == "granttap-mcp" }?.kind, .seen)
        let back = try XCTUnwrap(fromChild.first { $0.name == "nodvox" })
        XCTAssertEqual(back.projectId, "p-app")
        XCTAssertEqual(back.kind, .relatedByBinding)
        XCTAssertTrue(ProjectRepositories.detail(back).contains("no graph dependency has been verified"))
        XCTAssertEqual(fromChild.first?.kind, .own)
        XCTAssertNil(fromChild.first?.projectId, "sharing a repository never joins Project authority")
    }

    func testTheSectionRendersWithAndWithoutAMap() {
        let model = AppModel()
        let mcp = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "p-mcp", projectId: "p-mcp",
            project: project("p-mcp", name: "granttap-mcp", repo: "github.com/sergii/granttap-mcp"),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1
        )
        model.meshSnapshots = ["p-app": snapshot(), "p-mcp": mcp]
        RenderProbe.render(NavigationView { List { ProjectRepositoriesSection(snapshot: snapshot(), model: model) } })
        RenderProbe.render(NavigationView { ProjectMeshView(snapshot: snapshot(), model: model) })
        var bare = snapshot()
        bare.peers = nil
        bare.bindings = nil
        RenderProbe.render(NavigationView { List { ProjectRepositoriesSection(snapshot: bare, model: model) } })
        XCTAssertEqual(ProjectRepositories.rows(snapshot: bare, projects: []).map(\.kind), [.own, .seen, .seen])
    }

    func testSameRepositoryNameDoesNotLinkDifferentProjectIdentity() {
        let unrelated = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "p-unrelated", projectId: "p-unrelated",
            project: project("p-unrelated", name: "granttap-site", repo: "github.com/other/granttap-site"),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1
        )
        let rows = ProjectRepositories.rows(snapshot: snapshot(), projects: [snapshot(), unrelated])
        XCTAssertNil(rows.first { $0.name == "granttap-site" }?.projectId)
    }

    func testBackboneDoesNotReplaceRepositoryIdentityWithMatchingLabel() {
        var source = snapshot()
        let own = source.project.canonicalRepositoryId
        let unrelated = "github.com/other/granttap-mcp"
        source.backbone = ProjectBackbone(
            projectId: source.projectId, head: "verified-head",
            nodes: [
                .init(kind: "repository", identity: own, displayName: "nodvox"),
                .init(kind: "repository", identity: unrelated, displayName: "granttap-mcp")
            ],
            relations: [.init(source: own, target: unrelated, relation: "depends_on", evidenceCount: 1)],
            pendingCandidateCount: 0
        )
        let graph = ProjectGraphModel.make(from: source)
        XCTAssertTrue(graph.edges.contains { $0.source == own && $0.target == unrelated })
        XCTAssertFalse(graph.edges.contains {
            $0.source == own && $0.target == "github.com/sergii/granttap-mcp"
        })
    }

    func testGraphDrawsOnlyDeclaredEdgesAndIncludesUnboundRepositories() {
        var source = snapshot()
        source.tasks = [ProjectMeshTask(
            taskId: "t1", projectId: "p-app", title: "Ship", goal: "Ship",
            state: "working", ownerSessionId: "s1", createdAt: 1, updatedAt: 2
        )]
        let graph = ProjectGraphModel.make(from: source)
        XCTAssertEqual(graph.nodes.map(\.name), ["nodvox", "granttap-mcp", "granttap-site", "other", "scratch"])
        XCTAssertEqual(graph.edges.count, 2, "duplicate map entries describe one road")
        XCTAssertTrue(graph.edges.contains {
            $0.source == "github.com/sergii/nodvox"
                && $0.target == "github.com/sergii/granttap-mcp"
        })
        XCTAssertTrue(graph.edges.contains { $0.target == "peer:granttap-site" })
        XCTAssertFalse(graph.edges.contains { $0.target == "github.com/sergii/scratch" })
        XCTAssertEqual(graph.nodes.first?.openTasks, 2)
        XCTAssertEqual(graph.nodes.first?.layers.map(\.kind),
                       [.repository, .computer, .computer, .task])
        XCTAssertEqual(graph.nodes.first(where: { $0.name == "other" })?.openTasks, 1)
    }

    func testGraphScreenShowsUnavailableAnalysisWithoutFabricatedTower() {
        RenderProbe.render(NavigationView { ProjectGraphView(snapshot: snapshot(), model: AppModel()) })
    }

    func testGraphScreenExplainsStaleBindingWithoutAcceptingInventedNodes() throws {
        var source = snapshot()
        source.peers = nil
        source.bindings = nil
        source.executions = []
        source.repositoryGraphs = [ProjectRepositoryGraph(
            projectId: "p-app", repositoryId: "github.com/sergii/nodvox",
            revision: "unverified", weavatrixVersion: "unknown",
            analysisStatus: "UNAVAILABLE", analysisErrorCode: "REPOSITORY_IDENTITY_MISMATCH",
            nodes: [], relations: [], totalNodes: 0, totalRelations: 0, truncated: false
        )]
        XCTAssertTrue(ProjectMeshWireValidator.validSnapshot(try JSONEncoder().encode(source)))
        RenderProbe.render(NavigationView { ProjectGraphView(snapshot: source, model: AppModel()) })
        source.repositoryGraphs?[0] = ProjectRepositoryGraph(
            projectId: "p-app", repositoryId: "github.com/sergii/nodvox",
            revision: "unverified", weavatrixVersion: "unknown",
            analysisStatus: "UNAVAILABLE", analysisErrorCode: "REPOSITORY_IDENTITY_MISMATCH",
            nodes: [.init(id: "invented", kind: "component", label: "Invented")],
            relations: [], totalNodes: 1, totalRelations: 0, truncated: false
        )
        XCTAssertFalse(ProjectMeshWireValidator.validSnapshot(try JSONEncoder().encode(source)))
        var analyzed = source.repositoryGraphs![0]
        analyzed.analysisStatus = "COMPLETE"
        analyzed.analysisErrorCode = nil
        analyzed.architectureHypotheses = [.init(
            name: "onion", dimension: "dependency_direction", status: "CANDIDATE",
            evidence: ["src/infra → src/domain (imports)"], contradictions: [], unknowns: []
        )]
        source.repositoryGraphs = [analyzed]
        XCTAssertTrue(ProjectMeshWireValidator.validSnapshot(try JSONEncoder().encode(source)))
    }

    func testGraphScreenRendersObservedArchitectureAndPartialEvidence() throws {
        var source = snapshot()
        let repositoryId = "github.com/sergii/nodvox"
        let nodes: [ProjectRepositoryGraph.Node] = [
            .init(id: "component:app", kind: "component", label: "apps/ios"),
            .init(id: "component:runtime", kind: "component", label: "runtime"),
        ]
        source.repositoryGraphs = [ProjectRepositoryGraph(
            projectId: "p-app", repositoryId: repositoryId, revision: "sha-1",
            weavatrixVersion: "2.17.1", analysisId: "analysis-1", analysisStatus: "INCOMPLETE",
            nodes: nodes, relations: [.init(
                source: "component:app", target: "component:runtime",
                relation: "depends_on", evidenceCount: 2
            )], totalNodes: 2, totalRelations: 1, truncated: true
        )]
        XCTAssertEqual(source.repositoryGraphs?.first?.relations.first?.evidenceCount, 2)
        RenderProbe.render(NavigationView { ProjectGraphView(snapshot: source, model: AppModel()) })
        var withHypothesis = source.repositoryGraphs![0]
        withHypothesis.architectureHypotheses = [.init(
            name: "onion", dimension: "dependency_direction", status: "SUPPORTED",
            evidence: ["src/infra/mod.rs → src/domain/mod.rs (implements)"],
            contradictions: [], unknowns: ["runtime composition unverified"]
        )]
        source.repositoryGraphs = [withHypothesis]
        let decoded = try JSONDecoder().decode(ProjectRepositoryGraph.self,
                                               from: JSONEncoder().encode(withHypothesis))
        XCTAssertEqual(decoded.architectureHypotheses?.first?.status, "SUPPORTED")
        RenderProbe.render(NavigationView { ProjectGraphView(snapshot: source, model: AppModel()) })
        RenderProbe.render(ProjectMeshStatisticsView(snapshot: source, model: AppModel()))
        source.repositoryGraphs = [ProjectRepositoryGraph(
            projectId: "p-app", repositoryId: repositoryId, revision: "sha-2",
            weavatrixVersion: "2.17.1", analysisId: "analysis-2", analysisStatus: "COMPLETE",
            nodes: nodes, relations: [], totalNodes: 2, totalRelations: 0, truncated: false
        )]
        RenderProbe.render(NavigationView { ProjectGraphView(snapshot: source, model: AppModel()) })
        source.repositoryGraphs = [ProjectRepositoryGraph(
            projectId: "p-app", repositoryId: repositoryId, revision: "legacy",
            weavatrixVersion: "unknown", nodes: nodes, relations: [],
            totalNodes: 2, totalRelations: 0, truncated: false
        )]
        RenderProbe.render(NavigationView { ProjectGraphView(snapshot: source, model: AppModel()) })
    }

    func testGraphInspectorRendersOwnAndUnboundRepositoryRelations() {
        let graph = ProjectGraphModel.make(from: snapshot())
        let own = graph.nodes.first { $0.isOwn }!
        let unbound = graph.nodes.first { $0.name == "granttap-site" }!
        XCTAssertEqual(own.openTasks, 2)
        XCTAssertFalse(unbound.available)
        RenderProbe.render(ProjectGraphInspector(node: own, graph: graph, onClose: {}))
        RenderProbe.render(ProjectGraphInspector(node: unbound, graph: graph, onClose: {}))
    }
}
