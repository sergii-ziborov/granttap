import SwiftUI
import XCTest
@testable import GrantTap

/// One conversation that arrived as two Tasks, rejoined: the stale Task
/// leaves, and everything written against it moves with the survivor.
@MainActor
final class ProjectMeshRejoinTests: XCTestCase {
    private let now = ProjectMeshConvergenceFixtures.now

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

    func testAChatSplitAcrossTwoTasksIsRejoinedAndTheStaleTaskLeaves() {
        let model = AppModel()
        model.agentMeshPreferences = .defaults

        // What a Mac renamed by its network left on the phone: one chat, two
        // Tasks, each holding the summary frozen when it was made. Tasks merge
        // by id and are never removed, so the stale one outlived the computer
        // that published it and the list showed the chat twice.
        var split = ProjectMeshConvergenceFixtures.snapshot(generatedAt: now)
        split.tasks = [
            .init(taskId: "task", projectId: "project", title: "Pairing",
                  goal: "Refactor", state: "working", ownerSessionId: "claude",
                  createdAt: now, updatedAt: now),
            .init(taskId: "task-renamed", projectId: "project", title: "Pairing",
                  goal: "Publish it", state: "working", ownerSessionId: "claude",
                  createdAt: now + 5_000, updatedAt: now + 5_000),
        ]
        split.executions = [
            ProjectMeshConvergenceFixtures.execution(),
            .init(taskId: "task-renamed", sessionId: "claude", provider: "claude",
                  computerId: "Mac.lan", workspace: "/repo", branch: "claude/pairing",
                  worktree: "/repo", uncommitted: false, updatedAt: now + 5_000,
                  startedAt: now + 5_000, endedAt: nil),
        ]
        // Everything written against the stale Task has to follow it, or the
        // rejoin trades one wrong row for a claim, a dependency, and a history
        // that name a Task nothing can find.
        split.claims = [
            .init(claimId: "claim", projectId: "project", taskId: "task-renamed",
                  ownerSessionId: "claude", resource: "/repo", mode: "exclusive",
                  createdAt: now + 5_000, expiresAt: now + 600_000),
        ]
        split.dependencies = [
            .init(taskId: "task-renamed", dependsOnTaskId: "other",
                  summary: "Needs the relay", createdAt: now + 5_000),
        ]
        split.events = [
            .init(type: "mesh.event", sessionId: "task-renamed", eventId: "progress",
                  projectId: "project", taskId: "task-renamed", sourceSessionId: "claude",
                  targetSessionId: nil, eventType: "TASK_PROGRESS", createdAt: now + 5_000,
                  expiresAt: now + 600_000, payload: .init(summary: "Publishing")),
        ]
        model.receive(split, fromRoom: "source")

        let stored = model.meshSnapshots["project"]
        XCTAssertEqual(stored?.claims.map(\.taskId), ["task"], "a claim follows the survivor")
        XCTAssertEqual(stored?.dependencies.map(\.taskId), ["task"])
        XCTAssertEqual(
            model.meshEvents(forTaskId: "task").map(\.eventId), ["progress"],
            "the chat's history is not stranded on a Task that no longer exists"
        )
        XCTAssertEqual(stored?.tasks.count, 1, "one conversation is one Task")
        // The oldest survives: claims, dependencies, and events name it.
        XCTAssertEqual(stored?.tasks.first?.taskId, "task")
        XCTAssertEqual(
            Set(stored?.executions.map(\.taskId) ?? []), ["task"],
            "both computers' executions belong to the surviving Task"
        )
        XCTAssertEqual(stored?.executions.count, 2, "each computer keeps its execution")

        // A later snapshot that names only the survivor must not resurrect it.
        model.receive(ProjectMeshConvergenceFixtures.snapshot(generatedAt: now + 10_000), fromRoom: "source")
        XCTAssertEqual(model.meshSnapshots["project"]?.tasks.count, 1)

        // The list itself is what the person sees, so assert the rows.
        let items = TaskListCatalog.items(model: model, sessions: [])
        XCTAssertEqual(items.filter { $0.taskId == "task" }.count, 1)
        XCTAssertTrue(items.allSatisfy { $0.taskId != "task-renamed" })
    }

    func testADuplicateOnOneComputerIsRejoinedThoughItCarriesNoExecution() {
        let model = AppModel()
        model.agentMeshPreferences = .defaults

        // An execution is keyed by computer, provider, and chat, so two Tasks
        // for one chat on one computer share an execution id and merge into a
        // single row. The Task left holding none is invisible to anything that
        // walks executions, and it is the row that stayed on screen.
        var split = ProjectMeshConvergenceFixtures.snapshot(generatedAt: now)
        split.tasks = [
            .init(taskId: "task", projectId: "project", title: "Pairing",
                  goal: "Refactor", state: "working", ownerSessionId: "claude",
                  createdAt: now, updatedAt: now),
            .init(taskId: "task-again", projectId: "project", title: "Pairing",
                  goal: "Publish it", state: "working", ownerSessionId: "claude",
                  createdAt: now + 5_000, updatedAt: now + 5_000),
        ]
        split.executions = [ProjectMeshConvergenceFixtures.execution()]
        model.receive(split, fromRoom: "source")

        let stored = model.meshSnapshots["project"]
        XCTAssertEqual(stored?.tasks.count, 1, "one chat is one Task, execution or not")
        XCTAssertEqual(stored?.tasks.first?.taskId, "task")
        XCTAssertEqual(TaskListCatalog.items(model: model, sessions: []).count, 1)
    }
}
