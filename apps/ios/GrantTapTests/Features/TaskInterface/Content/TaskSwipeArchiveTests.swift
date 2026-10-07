import XCTest
@testable import GrantTap

@MainActor
final class TaskSwipeArchiveTests: XCTestCase {
    func testArchivingATaskHidesEveryExecutionAndKeepsRestorableSnapshots() {
        let priorIds = UserDefaults.standard.object(forKey: "granttap.archived-sessions")
        let priorSnapshots = ArchivedSessionPersistence.load()
        defer {
            if let priorIds {
                UserDefaults.standard.set(priorIds, forKey: "granttap.archived-sessions")
            } else {
                UserDefaults.standard.removeObject(forKey: "granttap.archived-sessions")
            }
            ArchivedSessionPersistence.save(priorSnapshots)
        }

        let model = AppModel()
        model.archivedSessionIds = []
        model.archivedSessions = [:]
        let first = session("first")
        let second = session("second")
        model.sessions = [first, second]
        let item = TaskListItem(
            id: "task:project\u{1f}task", destination: .task(.init(projectId: "project", taskId: "task")),
            projectId: "project", taskId: "task", projectName: "Project", title: "Task",
            summary: nil, state: "working", ownerExecution: nil, currentSession: second,
            historicalExecutions: [], sessionIds: [first.sessionId, second.sessionId], lastActivityAt: 2
        )

        ContentView(modelOverride: model).archiveTask(item)

        XCTAssertTrue(model.isArchived(first.sessionId))
        XCTAssertTrue(model.isArchived(second.sessionId))
        XCTAssertEqual(Set(model.archivedSessions.keys), Set([first.sessionId, second.sessionId]))
        XCTAssertTrue(ArchivedSessionPersistence.load().keys.contains(first.sessionId))
    }

    func testTaskWithoutALiveExecutionStillRendersItsHistoryCard() {
        let model = AppModel()
        let route = TaskRoute(projectId: "project", taskId: "task")
        model.meshSnapshots["project"] = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "Project", repositoryRoot: "/repo",
                           canonicalRepositoryId: "github.com/x/project", createdAt: 1),
            tasks: [.init(taskId: "task", projectId: "project", title: "Past task",
                          goal: "Last known work", state: "finished", createdAt: 1, updatedAt: 2)],
            executions: [], claims: [], dependencies: [], events: [], generatedAt: 2
        )
        let item = try! XCTUnwrap(TaskListCatalog.items(model: model, sessions: []).first)
        let content = ContentView(modelOverride: model)

        RenderProbe.render(content.taskActionCard(item))

        XCTAssertNil(item.currentSession)
        XCTAssertEqual(item.destination, .task(route))
    }

    private func session(_ id: String) -> SessionInfo {
        SessionInfo(sessionId: id, agent: "codex", title: id, cwd: "/repo",
                    state: "working", startedAt: 1, lastActivityAt: 2,
                    tokensSession: 0, tokensLastTurn: 0)
    }
}
