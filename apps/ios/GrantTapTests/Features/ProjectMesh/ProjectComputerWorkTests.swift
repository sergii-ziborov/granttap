import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class ProjectComputerWorkTests: XCTestCase {
    private let now = 1_800_000_000_000.0

    private func snapshot() -> ProjectMeshSnapshot {
        ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "p", projectId: "p",
            project: .init(projectId: "p", name: "nodvox", repositoryRoot: "/nodvox", canonicalRepositoryId: "github.com/x/nodvox", createdAt: 1),
            tasks: [
                .init(taskId: "live", projectId: "p", title: "Live work", goal: "g", state: "working", ownerSessionId: "s-live", createdAt: 1, updatedAt: now - 10_000),
                .init(taskId: "recent", projectId: "p", title: "Recent work", goal: "g", state: "working", ownerSessionId: "s-recent", createdAt: 1, updatedAt: now - 600_000),
                .init(taskId: "stale", projectId: "p", title: "Stale work", goal: "g", state: "working", ownerSessionId: "s-stale", createdAt: 1, updatedAt: now - 7_200_000),
                .init(taskId: "done", projectId: "p", title: "Done work", goal: "g", state: "completed", ownerSessionId: "s-done", createdAt: 1, updatedAt: now - 5_000),
            ],
            executions: [
                .init(taskId: "live", sessionId: "s-live", provider: "claude", computerId: "Mac.lan", workspace: "/nodvox", activeAt: now - 3_600_000, startedAt: now - 7_200_000),
                .init(taskId: "recent", sessionId: "s-recent", provider: "codex", computerId: "Mac.lan", workspace: "/nodvox", activeAt: now - 300_000, startedAt: now - 7_200_000),
                .init(taskId: "stale", sessionId: "s-stale", provider: "codex", computerId: "Mac.lan", workspace: "/nodvox", activeAt: now - 7_200_000, startedAt: now - 9_000_000),
                .init(taskId: "done", sessionId: "s-done", provider: "claude", computerId: "Mac.lan", workspace: "/nodvox", activeAt: now - 1_000, startedAt: now - 7_200_000),
                .init(taskId: "live", sessionId: "s-air", provider: "claude", computerId: "Air.local", workspace: "/nodvox", startedAt: now - 7_200_000, endedAt: now - 3_600_000),
            ],
            claims: [], dependencies: [], events: [], generatedAt: now
        )
    }

    private func session(_ id: String, state: String, paused: Bool = false, at: Double? = nil) -> SessionInfo {
        var session = SessionInfo(sessionId: id, agent: "claude", title: id == "s-live" ? "Live work" : nil, state: state,
                                  startedAt: 1, lastActivityAt: at ?? now, tokensSession: 1, tokensLastTurn: 1)
        session.paused = paused
        return session
    }

    func testAComputerSaysWhichTaskItIsBusyWithNow() {
        let live = session("s-live", state: "working")
        let items = ProjectComputerWork.current(snapshot: snapshot(), endpointId: "Mac.lan", sessions: [live], now: now)
        XCTAssertEqual(items.map(\.taskId), ["recent", "live"], "the freshest execution first; the stale and the finished are left out")
        XCTAssertEqual(items.first?.working, false)
        XCTAssertEqual(items.last?.working, true)
        XCTAssertEqual(ProjectComputerWork.line(items), String(format: L("Last on: %@"), "Recent work · Codex +1"))

        let onlyLive = ProjectComputerWork.current(snapshot: snapshot(), endpointId: "Mac.lan", sessions: [live], now: now + 20 * 60 * 1_000)
        XCTAssertEqual(onlyLive.map(\.taskId), ["live"], "a working chat counts however old its execution reads")
        XCTAssertEqual(ProjectComputerWork.line(onlyLive), String(format: L("Working on: %@"), "Live work · Claude"))

        let paused = session("s-live", state: "working", paused: true)
        XCTAssertTrue(ProjectComputerWork.current(snapshot: snapshot(), endpointId: "Mac.lan", sessions: [paused], now: now + 20 * 60 * 1_000).isEmpty,
                      "a paused chat is not work in progress")
        XCTAssertTrue(ProjectComputerWork.current(snapshot: snapshot(), endpointId: "Air.local", sessions: [], now: now).isEmpty, "its execution ended")
        XCTAssertNil(ProjectComputerWork.line([]))
    }

    func testTasksReadAsATimeline() {
        let sessions = [session("s-stale", state: "idle", at: now - 100)]
        let ordered = ProjectMeshRecency.ordered(snapshot().tasks, snapshot: snapshot(), sessions: sessions)
        XCTAssertEqual(ordered.map(\.taskId), ["stale", "done", "live", "recent"],
                       "the chat that spoke a moment ago outranks its old execution; then the Task's own update; then the executions")
        XCTAssertEqual(ProjectMeshRecency.lastActiveAt(snapshot().tasks[0], snapshot: snapshot(), sessions: []), now - 10_000,
                       "the Task's own update is the latest moment known")
        XCTAssertEqual(ProjectMeshRecency.lastActiveAt(snapshot().tasks[3], snapshot: snapshot(), sessions: []), now - 1_000)
        let tie = ProjectMeshRecency.ordered([snapshot().tasks[0], snapshot().tasks[0]], snapshot: snapshot(), sessions: [])
        XCTAssertEqual(tie.count, 2)

        let row = ProjectMeshTaskRow(task: snapshot().tasks[0], execution: snapshot().executions[0], lastActiveAt: now - 7_200_000)
        XCTAssertTrue(row.recencyLine?.hasPrefix(L("Last active")) == true)
        XCTAssertNil(ProjectMeshTaskRow(task: snapshot().tasks[0], execution: nil, lastActiveAt: 0).recencyLine)
        RenderProbe.render(List { row })

        let open = TaskRouteView.timingLine(snapshot().executions[1], now: now)
        XCTAssertTrue(open.contains(L("last active")), open)
        XCTAssertTrue(open.hasPrefix(String(format: L("started %@"), ReportBuilder.stamp(now - 7_200_000))))
        let ended = TaskRouteView.timingLine(snapshot().executions[4], now: now)
        XCTAssertTrue(ended.contains(String(format: L("ended %@"), ReportBuilder.stamp(now - 3_600_000))), ended)
    }

    func testAPausedChatReadsAsPausedEverywhere() {
        let task = snapshot().tasks[0]
        let paused = session("s-live", state: "working", paused: true)
        XCTAssertEqual(ProjectMeshTaskPresentation.state(task: task, execution: snapshot().executions[0], currentSession: paused), "paused")
        XCTAssertEqual(ProjectMeshTaskPresentation.label("paused"), L("Paused"))
        XCTAssertEqual(ProjectMeshTaskPresentation.state(task: task, execution: snapshot().executions[0], currentSession: session("s-live", state: "working")), "working")

        let item = TaskListItem(
            id: "task:live", destination: .task(.init(projectId: "p", taskId: "live")), projectId: "p", taskId: "live",
            projectName: "nodvox", title: "Live work", summary: nil, state: "working", ownerExecution: snapshot().executions[0],
            currentSession: paused, historicalExecutions: [], sessionIds: ["s-live"], lastActivityAt: now
        )
        let card = TaskListCard(item: item)
        XCTAssertEqual(card.presence, .waiting)
        XCTAssertEqual(card.stateLabel, L("Paused"))
        RenderProbe.render(card)
    }

    func testTheScreensCarryTheNewLines() {
        let model = AppModel()
        model.meshSnapshots = ["p": snapshot()]
        model.sessions = [session("s-live", state: "working")]
        RenderProbe.render(NavigationView { ProjectMeshView(snapshot: snapshot(), model: model) })
        RenderProbe.render(NavigationView { ProjectMembersView(snapshot: snapshot(), model: model) })
        RenderProbe.render(NavigationView { ProjectMeshStatusView(snapshot: snapshot(), model: model) })
        RenderProbe.render(NavigationView {
            TaskRouteView(route: .init(projectId: "p", taskId: "live"), model: model, onOpenSession: { _ in }, presentedAsSheet: false)
        })
        RenderProbe.render(List {
            ProjectComputerRow(computer: .init(endpointId: "Mac.lan", displayName: "Mac", repositoryCount: 1, available: true),
                               work: ProjectComputerWork.current(snapshot: snapshot(), endpointId: "Mac.lan", sessions: model.sessions, now: now))
            ProjectComputerUsageRow(usage: .init(endpointId: "Mac.lan", calls: 3, failures: 0, cpuTimeMs: 10, peakMemoryBytes: 10), model: model,
                                    work: ProjectComputerWork.current(snapshot: snapshot(), endpointId: "Mac.lan", sessions: model.sessions, now: now))
        })
    }
}
