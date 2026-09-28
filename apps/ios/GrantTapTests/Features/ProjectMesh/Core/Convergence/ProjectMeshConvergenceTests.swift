import SwiftUI
import XCTest
@testable import GrantTap

/// A Task keeps one identity while snapshots and events arrive late, twice, and
/// from several computers.
@MainActor
final class ProjectMeshConvergenceTests: XCTestCase {
    private let now = 1_800_000_000_000.0

    override func setUp() {
        super.setUp()
        ProjectMeshPersistence.clear()
        AgentMeshPreferencesStore.save(.defaults)
    }

    override func tearDown() {
        ProjectMeshPersistence.clear()
        AgentMeshPreferencesStore.save(.defaults)
        super.tearDown()
    }

    func testALateSnapshotNeverRestoresAPreviousOwnerOrReopensFinishedWork() {
        let model = AppModel()
        model.agentMeshPreferences = .defaults
        let stale = ProjectMeshConvergenceFixtures.snapshot(generatedAt: now)
        model.receive(stale, fromRoom: "source")

        var moved = ProjectMeshConvergenceFixtures.snapshot(generatedAt: now + 10)
        moved.tasks[0].ownerSessionId = "codex"
        moved.tasks[0].state = "completed"
        moved.tasks[0].revision = 3
        moved.tasks[0].updatedAt = now + 10
        model.receive(moved, fromRoom: "source")
        XCTAssertEqual(model.meshSnapshots["project"]?.tasks.first?.ownerSessionId, "codex")

        model.receive(stale, fromRoom: "source")
        let task = model.meshSnapshots["project"]?.tasks.first
        XCTAssertEqual(task?.ownerSessionId, "codex", "an old snapshot cannot restore an owner")
        XCTAssertEqual(task?.state, "completed", "an old snapshot cannot reopen finished work")
        XCTAssertEqual(task?.revision, 3)
    }

    func testAReplayedReceiptFromAFormerOwnerCannotMoveTheTask() throws {
        let model = AppModel()
        model.agentMeshPreferences = .defaults
        var state = ProjectMeshConvergenceFixtures.snapshot(generatedAt: now)
        state.events = [ProjectMeshConvergenceFixtures.request(id: "to-codex", capsule: ProjectMeshConvergenceFixtures.capsule(targetProvider: "codex"))]
        model.receive(state, fromRoom: "source")

        model.receive(try ProjectMeshConvergenceFixtures.accepted(id: "accept-codex", targetProvider: "codex",
                                   target: "codex", at: now + 20), fromRoom: "source")
        XCTAssertEqual(model.meshSnapshots["project"]?.tasks.first?.ownerSessionId, "codex")
        XCTAssertEqual(model.meshSnapshots["project"]?.tasks.first?.revision, 1)

        // A handoff the previous owner had already published finally reaches cursor.
        model.receive(ProjectMeshConvergenceFixtures.request(id: "to-cursor", capsule: ProjectMeshConvergenceFixtures.capsule(targetProvider: "cursor")),
                      fromRoom: "source")
        model.receive(try ProjectMeshConvergenceFixtures.accepted(id: "accept-cursor", targetProvider: "cursor",
                                   target: "cursor", at: now + 30), fromRoom: "source")
        XCTAssertEqual(
            model.meshSnapshots["project"]?.tasks.first?.ownerSessionId, "codex",
            "only the session that owns the task now may hand it on"
        )
    }

    func testAnExecutionClosedByAHandoffStaysClosedAndOpensNoChat() {
        let model = AppModel()
        model.agentMeshPreferences = .defaults
        var closed = ProjectMeshConvergenceFixtures.snapshot(generatedAt: now + 10)
        closed.executions[0].endedAt = now + 5
        closed.executions[0].updatedAt = now + 5
        closed.tasks[0].ownerSessionId = "codex-remote"
        closed.tasks[0].revision = 2
        closed.executions.append(ExecutionSessionLink(
            taskId: "task", sessionId: "codex-remote", provider: "codex",
            computerId: "Workstation", workspace: "/repo", branch: "codex/pairing",
            worktree: "/repo", uncommitted: false, updatedAt: now + 5, startedAt: now + 5
        ))
        model.receive(closed, fromRoom: "source")
        model.receive(ProjectMeshConvergenceFixtures.snapshot(generatedAt: now), fromRoom: "source")

        let previous = model.meshSnapshots["project"]?.executions
            .first { $0.sessionId == "claude" }
        XCTAssertEqual(previous?.endedAt, now + 5, "a handed-off execution stays closed")
        model.sessions = [ProjectMeshConvergenceFixtures.session()]
        let view = TaskRouteView(
            route: TaskRoute(projectId: "project", taskId: "task"), model: model
        ) { _ in }
        XCTAssertNil(view.localSession, "the previous execution never becomes a route again")
    }

    func testAWorkingTreeGrantTapCouldNotReadBlocksTheHandoff() {
        var unknown = ProjectMeshConvergenceFixtures.snapshot(generatedAt: now)
        unknown.executions[0].uncommitted = nil
        let blocked = TaskHandoffReadiness.checks(
            session: ProjectMeshConvergenceFixtures.session(), snapshot: unknown,
            destinationSelected: true, targetProviderEnabled: true
        )
        XCTAssertEqual(blocked.first { $0.id == "workingTree" }?.ready, false)
        XCTAssertEqual(
            TaskHandoffReadiness.blockedReason(blocked),
            TaskHandoffReadiness.unreadableWorkingTreeReason
        )

        var clean = ProjectMeshConvergenceFixtures.snapshot(generatedAt: now)
        clean.executions[0].uncommitted = false
        XCTAssertTrue(TaskHandoffReadiness.isReady(TaskHandoffReadiness.checks(
            session: ProjectMeshConvergenceFixtures.session(), snapshot: clean,
            destinationSelected: true, targetProviderEnabled: true
        )))
    }

    func testATaskWhoseSessionIsGoneStopsClaimingToBeWorking() {
        let model = AppModel()
        model.agentMeshPreferences = .defaults
        var abandoned = ProjectMeshConvergenceFixtures.snapshot(generatedAt: now)
        abandoned.tasks[0].state = "working"
        abandoned.executions[0].endedAt = now - 1_000
        model.meshSnapshots = ["project": abandoned]
        model.sessions = []
        let content = ContentView(modelOverride: model)
        let item = content.activeTaskItems.first

        XCTAssertNil(item, "a task nothing is running is history, not active work")
        let listed = TaskListCatalog.items(model: model, sessions: []).first
        XCTAssertEqual(listed?.state, "working", "the published state is preserved, not rewritten")
        XCTAssertEqual(listed?.hasOpenExecution, false)
        XCTAssertEqual(listed.map(content.health), .idle, "a dead chat is never presented as working")
        if let listed {
            XCTAssertEqual(TaskListCard(item: listed).presence, .idle)
            XCTAssertEqual(TaskListCard(item: listed).stateLabel, L("Idle"))
        }
    }

    func testTwoComputersHoldingTheSameRevisionConvergeOnOneTask() {
        var working = ProjectMeshConvergenceFixtures.task()
        working.revision = 4
        var finished = ProjectMeshConvergenceFixtures.task()
        finished.revision = 4
        finished.state = "completed"
        finished.ownerSessionId = "codex"
        XCTAssertEqual(ProjectMeshConvergence.preferred(working, finished), finished)
        XCTAssertEqual(ProjectMeshConvergence.preferred(finished, working), finished)

        var blocked = working
        blocked.state = "blocked"
        XCTAssertEqual(ProjectMeshConvergence.preferred(working, blocked),
                       ProjectMeshConvergence.preferred(blocked, working))

        let live = ProjectMeshConvergenceFixtures.execution()
        var ended = live
        ended.endedAt = now + 10
        XCTAssertEqual(ProjectMeshConvergence.preferred(live, ended).endedAt, now + 10)
        XCTAssertEqual(ProjectMeshConvergence.preferred(ended, live).endedAt, now + 10)
        var fresher = live
        fresher.uncommitted = true
        fresher.updatedAt = now + 5
        XCTAssertEqual(ProjectMeshConvergence.preferred(live, fresher).uncommitted, true)
    }
}
