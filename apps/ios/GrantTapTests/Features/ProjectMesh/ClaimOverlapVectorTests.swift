import XCTest
@testable import GrantTap

final class ClaimOverlapVectorTests: XCTestCase {
    func testSwiftPreflightMatchesRuntimeClaimOverlapVectors() {
        let vectors: [(String, String, Bool)] = [
            ("src/auth/**", "src/auth/login.ts", true),
            ("src/auth/*", "src/auth/x.ts", true),
            ("src/auth/*", "src/db/x.ts", false),
            ("Pairing.swift", "Pairing.swift", true),
            ("src/auth", "src/auth/login.ts", true),
        ]
        for (left, right, expected) in vectors {
            XCTAssertEqual(
                TaskHandoffReadiness.resourcesOverlap(left, right), expected,
                "\(left) vs \(right)"
            )
        }
    }

    /// Shared with the bridge's observed-claims test: change one, change both.
    func testModuleRootAndOverlapKindMatchTheBridgeVectors() {
        let roots: [(String, String)] = [
            ("apps/ios/GrantTap/Features/ProjectMesh/TaskRouteView.swift", "apps/ios/GrantTap/Features/ProjectMesh"),
            ("apps/bridge/src/mesh/store.ts", "apps/bridge/src/mesh"),
            ("crates/granttap-engine-core/src/backbone.rs", "crates/granttap-engine-core"),
            ("packages/protocol/messages/mesh.ts", "packages/protocol"),
            ("README.md", ""),
            ("docs/product/MARKETING.md", "docs/product"),
        ]
        for (path, expected) in roots {
            XCTAssertEqual(TaskHandoffReadiness.moduleRoot(path), expected, path)
        }
        XCTAssertEqual(TaskHandoffReadiness.overlapKind("apps/bridge/src/mesh/store.ts", "apps/bridge/src/mesh/store.ts"), .file)
        XCTAssertEqual(TaskHandoffReadiness.overlapKind("apps/bridge/src/mesh/**", "apps/bridge/src/mesh/store.ts"), .file)
        XCTAssertEqual(TaskHandoffReadiness.overlapKind("apps/bridge/src/mesh/store.ts", "apps/bridge/src/mesh/catalog.ts"), .module)
        XCTAssertNil(TaskHandoffReadiness.overlapKind("apps/bridge/src/mesh/store.ts", "apps/bridge/src/policy/effective-action.ts"))
        XCTAssertNil(TaskHandoffReadiness.overlapKind("README.md", "LICENSE"), "top-level files share no module")

        // The warning row: ready, flagged, never blocking.
        let session = SessionInfo(
            sessionId: "mine", agent: "claude", taskId: "task-a", title: "A", state: "working",
            startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0
        )
        let snapshot = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "GrantTap", repositoryRoot: "/repo",
                           canonicalRepositoryId: "repo", createdAt: 1),
            tasks: [], executions: [],
            claims: [
                .init(claimId: "a", projectId: "project", taskId: "task-a", ownerSessionId: "mine",
                      resource: "apps/bridge/src/mesh/store.ts", mode: "intent", createdAt: 1, expiresAt: 9e15),
                .init(claimId: "b", projectId: "project", taskId: "task-b", ownerSessionId: "theirs",
                      resource: "apps/bridge/src/mesh/catalog.ts", mode: "intent", createdAt: 1, expiresAt: 9e15),
            ],
            dependencies: [], events: [], generatedAt: 1
        )
        let checks = TaskHandoffReadiness.checks(
            session: session, snapshot: snapshot, destinationSelected: true, targetProviderEnabled: true
        )
        let module = checks.first { $0.id == "module" }
        XCTAssertEqual(module?.ready, true)
        XCTAssertEqual(module?.warning, true)
        XCTAssertTrue(module?.detail.contains("theirs") == true)
        XCTAssertEqual(checks.first { $0.id == "claims" }?.ready, true, "a module neighbour is not a file conflict")
    }

    /// Uncommitted work blocks a plain move and is released by a checkpoint.
    func testACheckpointReleasesADirtyWorkingTreeAsAWarningNotABlock() {
        let session = SessionInfo(
            sessionId: "mine", agent: "claude", taskId: "task-a", title: "A", state: "working",
            startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0
        )
        var snapshot = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "GrantTap", repositoryRoot: "/repo",
                           canonicalRepositoryId: "repo", createdAt: 1),
            tasks: [], executions: [
                .init(taskId: "task-a", sessionId: "mine", provider: "claude", computerId: "MacBook",
                      workspace: "/repo", uncommitted: true, startedAt: 1),
            ],
            claims: [], dependencies: [], events: [], generatedAt: 1
        )
        let plain = TaskHandoffReadiness.checks(
            session: session, snapshot: snapshot, destinationSelected: true, targetProviderEnabled: true
        )
        XCTAssertEqual(plain.first { $0.id == "workingTree" }?.ready, false)
        XCTAssertFalse(TaskHandoffReadiness.isReady(plain))

        let checkpointed = TaskHandoffReadiness.checks(
            session: session, snapshot: snapshot, destinationSelected: true, targetProviderEnabled: true,
            checkpoint: true
        )
        let tree = checkpointed.first { $0.id == "workingTree" }
        XCTAssertEqual(tree?.ready, true)
        XCTAssertEqual(tree?.warning, true, "ready, but the person should see what will happen")
        XCTAssertTrue(TaskHandoffReadiness.isReady(checkpointed))

        // A clean tree needs no checkpoint and gains no warning from the flag.
        snapshot.executions[0].uncommitted = false
        let clean = TaskHandoffReadiness.checks(
            session: session, snapshot: snapshot, destinationSelected: true, targetProviderEnabled: true,
            checkpoint: true
        )
        XCTAssertEqual(clean.first { $0.id == "workingTree" }?.warning, false)
    }

    /// The Task screen names who else is in this Task's files and modules.
    @MainActor
    func testTheTaskScreenNamesNeighboursByFileAndByModule() {
        let model = AppModel()
        model.meshSnapshots["project"] = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "GrantTap", repositoryRoot: "/repo",
                           canonicalRepositoryId: "repo", createdAt: 1),
            tasks: [.init(taskId: "task-a", projectId: "project", title: "A", goal: "A",
                          state: "working", createdAt: 1, updatedAt: 1)],
            executions: [],
            claims: [
                .init(claimId: "a", projectId: "project", taskId: "task-a", ownerSessionId: "mine",
                      resource: "apps/bridge/src/mesh/store.ts", mode: "intent", createdAt: 1, expiresAt: 9e15),
                .init(claimId: "b", projectId: "project", taskId: "task-b", ownerSessionId: "theirs",
                      resource: "apps/bridge/src/mesh/catalog.ts", mode: "intent", createdAt: 1, expiresAt: 9e15),
                .init(claimId: "c", projectId: "project", taskId: "task-c", ownerSessionId: "third",
                      resource: "apps/bridge/src/mesh/store.ts", mode: "claim", createdAt: 1, expiresAt: 9e15),
                .init(claimId: "d", projectId: "project", taskId: "task-d", ownerSessionId: "far",
                      resource: "docs/README.md", mode: "claim", createdAt: 1, expiresAt: 9e15),
            ],
            dependencies: [], events: [], generatedAt: 1
        )
        let view = TaskRouteView(
            route: .init(projectId: "project", taskId: "task-a"), model: model, onOpenSession: { _ in }
        )
        let kinds = Dictionary(uniqueKeysWithValues: view.neighbours.map { ($0.claim.ownerSessionId, $0.kind) })
        XCTAssertEqual(kinds["third"], .file, "the same file is a conflict")
        XCTAssertEqual(kinds["theirs"], .module, "the same module is the warning before it")
        XCTAssertNil(kinds["far"], "a file in another module is nobody's business")
        RenderProbe.render(view)
    }

    /// Shared with the bridge's integration-map test: change one, change both.
    @MainActor func testTheOtherSideOfARepositoryIsFoundFromEitherSidesStatement() {
        let api = "github.com/example/payments-api"
        let worker = "github.com/example/payment-worker"
        func binding(_ repositoryId: String, _ name: String) -> ProjectBindingSummary {
            .init(bindingId: "b-\(name)", projectId: "project", endpointId: "mac-a",
                  repositoryId: repositoryId, displayName: name, available: true)
        }
        func task(_ taskId: String) -> ProjectMeshTask {
            .init(taskId: taskId, projectId: "project", title: "\(taskId) title", goal: "goal",
                  state: "working", ownerSessionId: "\(taskId) owner", createdAt: 1, updatedAt: 1)
        }
        func execution(_ taskId: String, _ repositoryId: String?, workspace: String,
                       endedAt: Double? = nil) -> ExecutionSessionLink {
            .init(taskId: taskId, sessionId: "\(taskId) chat", provider: "claude", computerId: "mac-a",
                  workspace: workspace, repositoryId: repositoryId, startedAt: 1, endedAt: endedAt)
        }
        let peer = ProjectIntegrationPeer(
            projectId: "project", repositoryId: api, peer: "Payment-Worker", via: "kafka",
            relation: "produces", through: "payment.completed", updatedAt: 1
        )
        func snapshot(root: String? = "/repo/payments-api",
                      executions: [ExecutionSessionLink]) -> ProjectMeshSnapshot {
            ProjectMeshSnapshot(
                type: "mesh.snapshot", sessionId: "project", projectId: "project",
                project: .init(projectId: "project", name: "Payments", repositoryRoot: root,
                               canonicalRepositoryId: api, createdAt: 1),
                bindings: [binding(api, "payments-api"), binding(worker, "payment-worker")],
                peers: [peer], tasks: [task("task-api"), task("task-worker")],
                executions: executions, claims: [], dependencies: [], events: [], generatedAt: 1
            )
        }
        let both = snapshot(executions: [
            execution("task-api", api, workspace: "/repo/payments-api"),
            execution("task-worker", worker, workspace: "/repo/payment-worker"),
        ])

        XCTAssertEqual(ProjectOtherSide.repositoryNames(binding(worker, "Worker checkout")),
                       ["payment-worker", "worker checkout"])
        XCTAssertEqual(ProjectOtherSide.otherSides(of: api, in: both).map(\.repositoryId), [worker],
                       "stated by this side")
        XCTAssertEqual(ProjectOtherSide.otherSides(of: worker, in: both).map(\.repositoryId), [api],
                       "stated by the other side")

        let fromApi = ProjectOtherSide.rows(in: both, taskId: "task-api")
        XCTAssertEqual(fromApi.count, 1)
        XCTAssertEqual(fromApi.first?.taskId, "task-worker")
        XCTAssertEqual(fromApi.first?.through, "payment.completed")
        XCTAssertEqual(fromApi.first?.statedBy, api)
        XCTAssertEqual(ProjectOtherSide.rows(in: both, taskId: "task-worker").first?.taskId, "task-api",
                       "the worker sees the api Task too")
        XCTAssertEqual(ProjectOtherSide.describe(fromApi[0], in: both),
                       "payments-api produces payment.completed · payment-worker")

        // An execution that ended is not on the other side of anything.
        let ended = snapshot(executions: [
            execution("task-api", api, workspace: "/repo/payments-api"),
            execution("task-worker", worker, workspace: "/repo/payment-worker", endedAt: 2),
        ])
        XCTAssertTrue(ProjectOtherSide.rows(in: ended, taskId: "task-api").isEmpty)

        // Without a repository id, the Project root still places an execution.
        let byRoot = snapshot(executions: [
            execution("task-api", nil, workspace: "/repo/payments-api/apps"),
            execution("task-worker", worker, workspace: "/repo/payment-worker"),
        ])
        XCTAssertEqual(ProjectOtherSide.rows(in: byRoot, taskId: "task-api").first?.taskId, "task-worker")
        let rootless = snapshot(root: nil, executions: byRoot.executions)
        XCTAssertTrue(ProjectOtherSide.rows(in: rootless, taskId: "task-api").isEmpty)

        let model = AppModel()
        model.meshSnapshots["project"] = both
        let view = TaskRouteView(
            route: .init(projectId: "project", taskId: "task-api"), model: model, onOpenSession: { _ in }
        )
        XCTAssertEqual(view.otherSide.map(\.taskId), ["task-worker"])
        RenderProbe.render(view)
        RenderProbe.render(ProjectMeshStatusView(snapshot: both, model: model))
    }

    @MainActor func testTheOtherSideIsNamedAndPhrasedFromWhatTheMapStates() {
        let api = "github.com/example/payments-api"
        let snapshot = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "Payments", repositoryRoot: "/repo/payments-api/",
                           canonicalRepositoryId: api, createdAt: 1),
            bindings: [.init(bindingId: "b", projectId: "project", endpointId: "mac-a",
                             repositoryId: api, displayName: "payments-api", available: true)],
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1
        )
        XCTAssertEqual(ProjectOtherSide.displayName(of: api, in: snapshot), "payments-api")
        XCTAssertEqual(ProjectOtherSide.displayName(of: "github.com/example/other.git", in: snapshot), "other",
                       "an unbound repository is shown by its last path segment")
        XCTAssertEqual(ProjectOtherSide.displayName(of: "solo", in: snapshot), "solo")

        XCTAssertEqual(ProjectOtherSide.phrase(relation: "produces", through: "orders"), "produces orders")
        XCTAssertEqual(ProjectOtherSide.phrase(relation: "consumes", through: "orders"), "consumes orders")
        XCTAssertEqual(ProjectOtherSide.phrase(relation: "shares", through: "PostgreSQL / payments"),
                       "shares PostgreSQL / payments")
        XCTAssertEqual(ProjectOtherSide.phrase(relation: "calls", through: nil), "calls its API")
        XCTAssertEqual(ProjectOtherSide.phrase(relation: "called_by", through: nil), "is called by it")
        XCTAssertEqual(ProjectOtherSide.phrase(relation: "haunts", through: nil), "haunts",
                       "a relation the map invented is shown as it came")

        var hinted = ProjectBindingSummary(bindingId: "h", projectId: "project", endpointId: "mac-a",
                                           repositoryId: "github.com/example/payment-worker/",
                                           displayName: "", available: true)
        hinted.localPathHint = "/Users/me/dev/Worker-Checkout/"
        XCTAssertEqual(ProjectOtherSide.repositoryNames(hinted), ["worker-checkout", "payment-worker"])

        // A root written with a trailing slash still places the execution.
        let atRoot = ExecutionSessionLink(taskId: "t", sessionId: "c", provider: "claude", computerId: "mac-a",
                                          workspace: "/repo/payments-api/", startedAt: 1)
        XCTAssertEqual(ProjectOtherSide.repository(of: atRoot, in: snapshot), api)
        let elsewhere = ExecutionSessionLink(taskId: "t", sessionId: "c", provider: "claude", computerId: "mac-a",
                                             workspace: "/repo/other", startedAt: 1)
        XCTAssertNil(ProjectOtherSide.repository(of: elsewhere, in: snapshot))

        let peer = ProjectIntegrationPeer(projectId: "project", repositoryId: api, peer: "nobody",
                                          via: "api", relation: "calls", updatedAt: 1)
        var withPeer = snapshot
        withPeer.peers = [peer]
        XCTAssertTrue(ProjectOtherSide.otherSides(of: api, in: withPeer).isEmpty,
                      "a peer the Project does not bind has no side to show")
        RenderProbe.render(ProjectMeshStatusView(snapshot: withPeer, model: AppModel()))
    }
}
