#if targetEnvironment(macCatalyst)
import XCTest
@testable import GrantTap

@MainActor
final class MacLiveSessionProjectionTests: XCTestCase {
    func testCurrentNativeWorkAppearsAsWorkingDespiteAnOldClose() {
        let execution = execution()
        let task = task()
        let native = session()
        let projected = MacLiveSessionProjection.session(
            execution: execution, task: task, observed: [native], endpointId: "local")
        XCTAssertEqual(projected?.state, "working")
        let model = AppModel()
        model.meshSnapshots = ["p": snapshot(execution, task)]
        model.sessions = [projected!]
        let item = TaskListCatalog.items(model: model, sessions: model.sessions).first!
        XCTAssertEqual(item.state, "working")
        XCTAssertTrue(item.hasOpenExecution)
        XCTAssertFalse(item.isTerminal)
        XCTAssertEqual(item.summary, "Current progress")
    }

    func testIdleNativeReportDoesNotClaimWorkingFromRecentActivity() {
        var native = session()
        native.state = "idle"
        XCTAssertEqual(MacLiveSessionProjection.session(execution: execution(), task: task(),
            observed: [native], endpointId: "local")?.state, "idle")
    }

    func testWrongScopeAndFormerOwnersNeverReplaceTheCurrentExecution() {
        let native = session()
        for key in ["provider", "computer", "task", "project", "session"] {
            var wrong = native
            switch key {
            case "provider": wrong = session(agent: "claude")
            case "computer": wrong.computerId = "remote"
            case "task": wrong.taskId = "other"
            case "project": wrong.projectId = "other"
            default: wrong = session(sessionId: "other")
            }
            XCTAssertNil(MacLiveSessionProjection.session(execution: execution(), task: task(),
                observed: [wrong], endpointId: "local"))
        }
        var moved = task()
        moved.ownerSessionId = "new-owner"
        XCTAssertNil(MacLiveSessionProjection.session(execution: execution(), task: moved,
            observed: [native], endpointId: "local"))
        moved = task()
        moved.state = "completed"
        XCTAssertNil(MacLiveSessionProjection.session(execution: execution(), task: moved,
            observed: [native], endpointId: "local"))
    }

    func testAnOldReportCannotResurrectAClosedExecution() {
        var native = session()
        native.lastActivityAt = 50
        XCTAssertNil(MacLiveSessionProjection.session(execution: execution(), task: task(),
            observed: [native], endpointId: "local"))
    }

    func testExpiredOrForeignComputerCatalogDoesNotProvideLiveObservations() {
        let native = session()
        let report = MacLocalLiveCatalog(operation: "desktop.live_catalog", computer_id: "local",
            generated_at: 100_000, sessions: [native])
        XCTAssertEqual(report.observations(endpointId: "local", nowMs: 100_000), [native])
        XCTAssertTrue(report.observations(endpointId: "local", nowMs: 161_000).isEmpty)
        XCTAssertTrue(report.observations(endpointId: "remote", nowMs: 100_000).isEmpty)
    }

    private func execution() -> ExecutionSessionLink {
        .init(taskId: "t", sessionId: "s", provider: "codex", computerId: "local",
              workspace: "/test", activeAt: 100, startedAt: 1, endedAt: 60)
    }
    private func task() -> ProjectMeshTask {
        .init(taskId: "t", projectId: "p", title: "Test", goal: "Earlier result", state: "working",
              ownerSessionId: "s", createdAt: 1, updatedAt: 100)
    }
    private func session(sessionId: String = "s", agent: String = "codex") -> SessionInfo {
        .init(sessionId: sessionId, agent: agent, projectId: "p", taskId: "t", computerId: "local",
              title: "Test", summary: "Current progress", state: "working", startedAt: 1,
              lastActivityAt: 100, tokensSession: 0, tokensLastTurn: 0)
    }
    private func snapshot(_ execution: ExecutionSessionLink, _ task: ProjectMeshTask) -> ProjectMeshSnapshot {
        .init(type: "mesh.snapshot", sessionId: "p", projectId: "p",
              project: .init(projectId: "p", name: "Test", repositoryRoot: nil,
                             canonicalRepositoryId: "repo", createdAt: 1),
              tasks: [task], executions: [execution], claims: [], dependencies: [], events: [], generatedAt: 100)
    }
}
#endif
