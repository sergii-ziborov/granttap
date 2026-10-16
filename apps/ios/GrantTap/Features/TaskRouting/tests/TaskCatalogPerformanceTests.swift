import XCTest
@testable import GrantTap

@MainActor
final class TaskCatalogPerformanceTests: XCTestCase {
    func testBuildingLargeTabCatalogDoesNotRescanEveryExecutionForEveryTask() {
        let model = AppModel()
        model.demoMode = true
        let project = "navigation-load"
        let tasks = (0..<2_000).map { i in
            ProjectMeshTask(taskId: "task-\(i)", projectId: project, title: "Synthetic \(i)", goal: "",
                state: "working", ownerSessionId: "session-\(i)", createdAt: 1, updatedAt: 2)
        }
        let sessions = tasks.enumerated().map { i, task in
            SessionInfo(sessionId: "session-\(i)", agent: "codex", projectId: project, taskId: task.taskId,
                state: "working", startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        }
        model.meshSnapshots = [project: .init(type: "mesh.snapshot", sessionId: project, projectId: project,
            project: .init(projectId: project, name: "Synthetic", canonicalRepositoryId: "repo", createdAt: 1),
            tasks: tasks, executions: tasks.enumerated().map { i, task in
                .init(taskId: task.taskId, sessionId: "session-\(i)", provider: "codex",
                    computerId: "mac", workspace: "/synthetic", startedAt: 1)
            }, claims: [], dependencies: [], events: [], generatedAt: 2)]
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<4 {
            let rows = TaskListCatalog.items(model: model, sessions: sessions)
            XCTAssertEqual(rows.count, 2_000)
            XCTAssertTrue(rows.allSatisfy { $0.sessionIds.count == 1 && $0.hasOpenExecution })
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let evidence = XCTAttachment(string: "Four catalog builds / 2000 Tasks: \(elapsed) seconds")
        evidence.lifetime = .keepAlways
        add(evidence)
        XCTAssertLessThan(elapsed, 0.25, "Tab construction must index native sessions and executions once.")
        model.sessions = sessions
        let content = ContentView(modelOverride: model)
        let filterStart = ProcessInfo.processInfo.systemUptime
        XCTAssertEqual(content.filteredTaskItems.count, 2_000)
        let filterElapsed = ProcessInfo.processInfo.systemUptime - filterStart
        let filterEvidence = XCTAttachment(string: "Active filtering / 2000 open Tasks: \(filterElapsed) seconds")
        filterEvidence.lifetime = .keepAlways
        add(filterEvidence)
        XCTAssertLessThan(filterElapsed, 0.25, "Open Tasks do not require offscreen usage/route classification.")
    }
}
