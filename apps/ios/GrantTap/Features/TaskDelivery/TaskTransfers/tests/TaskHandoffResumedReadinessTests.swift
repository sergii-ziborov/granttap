import XCTest
@testable import GrantTap

@MainActor
final class TaskHandoffResumedReadinessTests: XCTestCase {
    func testResumedChatReportsDirtyCheckoutAndOffersCheckpoint() {
        let model = AppModel()
        model.meshSnapshots = ["project": snapshot(dirty: true)]
        let sheet = TaskHandoffSheet(session: session(), model: model)
        let check = checks(snapshot(dirty: true)).first { $0.id == "workingTree" }
        XCTAssertEqual(check?.detail, TaskHandoffReadiness.uncommittedReason)
        XCTAssertTrue(sheet.hasUncommittedWork)
        XCTAssertFalse(TaskHandoffReadiness.isReady(checks(snapshot(dirty: true))))
        XCTAssertTrue(TaskHandoffReadiness.isReady(checks(snapshot(dirty: true), checkpoint: true)))
    }

    func testResumedCleanChatCanTransferAfterOldExecutionClosure() {
        XCTAssertTrue(TaskHandoffReadiness.isReady(checks(snapshot(dirty: false))))
    }

    func testOldClosedChatDoesNotUseHistoricalCheckoutReading() {
        var chat = session()
        chat.lastActivityAt = 20
        let rows = TaskHandoffReadiness.checks(session: chat, snapshot: snapshot(dirty: false),
            destinationSelected: true, targetProviderEnabled: true)
        XCTAssertEqual(rows.first { $0.id == "workingTree" }?.detail,
                       TaskHandoffReadiness.unreadableWorkingTreeReason)
        XCTAssertFalse(TaskHandoffReadiness.isReady(rows))
    }

    func testAnotherComputerTaskOrProviderCannotMakeTheSourceReady() {
        for change in 0..<3 {
            var state = snapshot(dirty: false)
            let row = state.executions[0]
            state.executions = [.init(taskId: change == 0 ? "other" : row.taskId,
                sessionId: row.sessionId, provider: change == 1 ? "grok" : row.provider,
                computerId: change == 2 ? "other-mac" : row.computerId,
                workspace: row.workspace, uncommitted: false, updatedAt: 40, startedAt: 1)]
            XCTAssertFalse(TaskHandoffReadiness.isReady(checks(state)))
        }
    }

    func testMissingReadingsStillBlockCheckpoint() {
        var state = snapshot(dirty: false)
        state.executions[0].uncommitted = nil
        XCTAssertFalse(TaskHandoffReadiness.isReady(checks(state, checkpoint: true)))
    }

    private func checks(_ state: ProjectMeshSnapshot, checkpoint: Bool = false) -> [HandoffReadinessCheck] {
        TaskHandoffReadiness.checks(session: session(), snapshot: state,
            destinationSelected: true, targetProviderEnabled: true, checkpoint: checkpoint)
    }

    private func session() -> SessionInfo {
        .init(sessionId: "source", agent: "codex", projectId: "project", taskId: "task",
              computerId: "mac", title: "Existing task", cwd: "/repo", branch: "main",
              model: nil, state: "idle", startedAt: 1, lastActivityAt: 30,
              tokensSession: 0, tokensLastTurn: 0)
    }

    private func snapshot(dirty: Bool) -> ProjectMeshSnapshot {
        .init(type: "mesh.snapshot", sessionId: "project", projectId: "project",
              project: .init(projectId: "project", name: "Project", canonicalRepositoryId: "repo", createdAt: 1),
              tasks: [], executions: [.init(taskId: "task", sessionId: "source", provider: "codex",
                  computerId: "mac", workspace: "/repo", uncommitted: dirty,
                  updatedAt: 40, startedAt: 1, endedAt: 20)],
              claims: [], dependencies: [], events: [], generatedAt: 40)
    }
}
