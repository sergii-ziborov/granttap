import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class TaskRouteReadinessTests: XCTestCase {
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

    func testUncommittedWorkBlocksTheHandoffInsteadOfNarrowingIt() {
        let model = AppModel()
        model.agentMeshPreferences = .defaults
        model.meshSnapshots = ["project": snapshot(uncommitted: true)]
        model.connectionRegistry = .init(connections: [linked("source"), linked("target")],
                                         preferredId: "source")
        model.sessionSourceRooms["claude"] = ["source"]

        let sheet = TaskHandoffSheet(
            session: session(), model: model, initialTargetRoom: "target"
        )
        let checks = sheet.readinessChecks
        let workingTree = checks.first { $0.id == "workingTree" }
        XCTAssertEqual(workingTree?.ready, false)
        XCTAssertEqual(workingTree?.detail, TaskHandoffReadiness.uncommittedReason)
        XCTAssertFalse(sheet.isReady)
        XCTAssertFalse(sheet.isReadyForGrokBot)
        XCTAssertFalse(sheet.performHandoff(targetRoom: "target", targetProvider: "codex"))
        XCTAssertEqual(
            TaskHandoffReadiness.blockedReason(checks), TaskHandoffReadiness.uncommittedReason
        )
    }

    func testCleanTaskWithoutOverlapIsReadyAndClaimConflictsBlockIt() {
        let model = AppModel()
        model.agentMeshPreferences = .defaults
        model.meshSnapshots = ["project": snapshot(uncommitted: false)]
        model.connectionRegistry = .init(connections: [linked("source"), linked("target")],
                                         preferredId: "source")
        model.sessionSourceRooms["claude"] = ["source"]

        let ready = TaskHandoffSheet(
            session: session(), model: model, initialTargetRoom: "target"
        )
        XCTAssertTrue(ready.isReady)
        XCTAssertTrue(ready.performHandoff(targetRoom: "target", targetProvider: "codex"))
        XCTAssertTrue(TaskHandoffReadiness.isReady(TaskHandoffReadiness.checks(
            session: session(), snapshot: model.meshSnapshots["project"],
            destinationSelected: true, targetProviderEnabled: true
        )))

        var conflicted = snapshot(uncommitted: false)
        conflicted.claims = [
            claim(taskId: "task", owner: "claude", resource: "packages/pairing/**"),
            claim(taskId: "other-task", owner: "codex-other", resource: "packages/pairing/**"),
        ]
        model.meshSnapshots = ["project": conflicted]
        let blocked = TaskHandoffReadiness.checks(
            session: session(), snapshot: conflicted,
            destinationSelected: true, targetProviderEnabled: true
        )
        XCTAssertFalse(TaskHandoffReadiness.isReady(blocked))
        XCTAssertEqual(blocked.first { $0.id == "claims" }?.ready, false)
        XCTAssertTrue(blocked.first { $0.id == "claims" }?.detail.contains("codex-other") == true)
        let conflictedSheet = TaskHandoffSheet(
            session: session(), model: model, initialTargetRoom: "target"
        )
        XCTAssertFalse(conflictedSheet.performHandoff(targetRoom: "target", targetProvider: "codex"))
    }

    func testTaskRouteOpensWithoutAnyNativeSessionAndAnswersAnAgentQuestion() {
        let model = AppModel()
        model.agentMeshPreferences = .defaults
        var state = snapshot(uncommitted: false)
        state.executions = [ExecutionSessionLink(
            taskId: "task", sessionId: "grok-bot:qa:42", provider: "grok_bot", actorId: "qa",
            computerId: "grok-cloud", workspace: "/repo", branch: nil, worktree: nil,
            uncommitted: nil, startedAt: now, endedAt: nil
        )]
        state.tasks[0].ownerSessionId = "grok-bot:qa:42"
        model.meshSnapshots = ["project": state]

        let pairing = Pairing(relayUrl: "ws://127.0.0.1:1", room: String(repeating: "a", count: 32),
                              role: "phone", deviceName: "iPhone", senderId: "phone",
                              myPublicKey: "public", mySecretKey: "secret", peerPublicKey: "peer")
        let relay = RelayClient(pairing: pairing)
        model.relaysByRoom[pairing.room] = relay
        XCTAssertTrue(relay.installForwardedScopeKey(
            Data(repeating: 7, count: 32).base64EncodedString(), scopeId: "task"
        ))
        let question = ProjectMeshEvent(
            type: "mesh.event", sessionId: "task", eventId: "question", projectId: "project",
            taskId: "task", sourceSessionId: "grok-bot:qa:42", targetSessionId: nil,
            eventType: "AGENT_QUESTION", createdAt: now, expiresAt: now + 600_000,
            payload: .init(question: "Ship the release?", category: "product")
        )
        model.pendingMeshEvents = [question]
        model.meshEventSourceRooms["question"] = pairing.room

        // The owner has no native SessionInfo on this phone: Needs You must
        // still reach the Task instead of doing nothing.
        let route = TaskRoute(projectId: "project", taskId: "task")
        let view = TaskRouteView(route: route, model: model) { _ in }
        XCTAssertNil(view.localSession)
        XCTAssertEqual(view.pendingQuestion?.eventId, "question")
        XCTAssertEqual(view.executions.count, 1)
        render(view)

        model.answerMeshQuestion("question", text: "   ")
        XCTAssertEqual(model.pendingMeshEvents.count, 1, "an empty answer publishes nothing")
        model.answerMeshQuestion("question", text: "Yes, ship it")
        XCTAssertTrue(model.pendingMeshEvents.isEmpty)
        let answer = model.meshEvents(forTaskId: "task").first { $0.eventType == "AGENT_ANSWER" }
        XCTAssertEqual(answer?.payload.answer, "Yes, ship it")
        XCTAssertEqual(answer?.payload.questionEventId, "question")
        XCTAssertEqual(answer?.targetSessionId, "grok-bot:qa:42")
        model.answerMeshQuestion("question", text: "Second answer")
        relay.disconnect()
    }

    func testTaskRouteRendersClaimsTimelineAndTheLocalChatRoute() {
        let model = AppModel()
        model.agentMeshPreferences = .defaults
        var state = snapshot(uncommitted: true)
        state.tasks[0].goal = "Refactor the pairing crypto"
        state.claims = [claim(taskId: "task", owner: "claude", resource: "packages/pairing/**")]
        state.dependencies = [.init(taskId: "task", dependsOnTaskId: "other", summary: nil, createdAt: now)]
        state.events = [ProjectMeshEvent(
            type: "mesh.event", sessionId: "task", eventId: "progress", projectId: "project",
            taskId: "task", sourceSessionId: "claude", targetSessionId: nil,
            eventType: "TASK_PROGRESS", createdAt: now, expiresAt: now + 600_000,
            payload: .init(summary: "Crypto complete")
        )]
        model.meshSnapshots = ["project": state]
        model.sessions = [session()]

        var opened: SessionInfo?
        let view = TaskRouteView(
            route: TaskRoute(projectId: "project", taskId: "task"), model: model
        ) { opened = $0 }
        XCTAssertEqual(view.localSession?.sessionId, "claude")
        XCTAssertNil(view.pendingQuestion)
        XCTAssertEqual(view.claims.count, 1)
        XCTAssertEqual(view.events.count, 1)
        XCTAssertTrue(view.stateLine.contains(L("Idle")), "the chat is idle, and the Task screen says so the way the list does, not the raw task state")
        render(view)
        XCTAssertNil(opened)

        let empty = TaskRouteView(
            route: TaskRoute(projectId: "missing", taskId: "missing"), model: model
        ) { _ in }
        XCTAssertTrue(empty.executions.isEmpty)
        XCTAssertNil(empty.localSession)
        render(empty)
    }

    func testTaskRouteOpensAnExecutionChatRetainedInHistory() {
        let model = AppModel()
        model.agentMeshPreferences = .defaults
        let state = snapshot(uncommitted: false)
        model.meshSnapshots = ["project": state]
        model.sessions = []
        model.sessionHistory = [session()]

        var opened: SessionInfo?
        let view = TaskRouteView(
            route: TaskRoute(projectId: "project", taskId: "task"), model: model
        ) { opened = $0 }
        let execution = state.executions[0]

        XCTAssertEqual(view.localSession?.sessionId, "claude")
        XCTAssertEqual(view.session(for: execution)?.sessionId, "claude")
        XCTAssertTrue(view.openChat(for: execution))
        XCTAssertEqual(opened?.sessionId, "claude")
    }

    func testTaskRouteNeverReopensAPreviousNativeExecution() {
        let model = AppModel()
        model.agentMeshPreferences = .defaults
        var state = snapshot(uncommitted: false)
        state.executions.append(ExecutionSessionLink(
            taskId: "task", sessionId: "grok-bot:qa:42", provider: "grok_bot", actorId: "qa",
            computerId: "grok-cloud", workspace: "/repo", branch: nil, worktree: nil,
            uncommitted: nil, startedAt: now + 1, endedAt: nil
        ))
        state.tasks[0].ownerSessionId = "grok-bot:qa:42"
        model.meshSnapshots = ["project": state]
        model.sessions = [session()]

        let view = TaskRouteView(
            route: TaskRoute(projectId: "project", taskId: "task"), model: model
        ) { _ in }
        XCTAssertNil(view.localSession)
        XCTAssertEqual(view.ownerExecution?.sessionId, "grok-bot:qa:42")
        XCTAssertTrue(view.stateLine.contains("QA · Grok Bot"))
        XCTAssertFalse(view.stateLine.contains("grok-bot:qa:42"))
        render(view)
    }

    func testExecutionsDecodeTheUncommittedFlagFromTheWire() throws {
        let payload = Data("""
        {"taskId":"task","sessionId":"claude","provider":"claude","computerId":"MacBook",
         "workspace":"/repo","uncommitted":true,"startedAt":1}
        """.utf8)
        let execution = try JSONDecoder().decode(ExecutionSessionLink.self, from: payload)
        XCTAssertEqual(execution.uncommitted, true)
        let round = try JSONDecoder().decode(
            ExecutionSessionLink.self, from: JSONEncoder().encode(execution)
        )
        XCTAssertEqual(round.uncommitted, true)
    }

    private func snapshot(uncommitted: Bool) -> ProjectMeshSnapshot {
        ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "GrantTap", repositoryRoot: "/repo",
                           canonicalRepositoryId: "github.com/example/granttap",
                           baseRemote: nil, createdAt: now),
            tasks: [.init(taskId: "task", projectId: "project", title: "Pairing", goal: "Refactor",
                          state: "working", ownerSessionId: "claude", createdAt: now, updatedAt: now)],
            executions: [ExecutionSessionLink(
                taskId: "task", sessionId: "claude", provider: "claude", actorId: nil,
                computerId: "MacBook", workspace: "/repo", branch: "claude/pairing",
                worktree: "/repo", uncommitted: uncommitted, startedAt: now, endedAt: nil
            )],
            claims: [], dependencies: [], events: [], generatedAt: now
        )
    }

    private func claim(taskId: String, owner: String, resource: String) -> ProjectResourceClaim {
        .init(claimId: "\(taskId)-\(owner)", projectId: "project", taskId: taskId,
              ownerSessionId: owner, resource: resource, mode: "claim",
              createdAt: now, expiresAt: now + 600_000)
    }

    private func linked(_ room: String) -> LinkedComputer {
        let machine = room == "source" ? "MacBook" : "Workstation"
        return .init(
            id: room,
            pairing: Pairing(relayUrl: "ws://127.0.0.1:1", room: String(repeating: room.first!, count: 32),
                             role: "phone", deviceName: machine, senderId: "phone",
                             myPublicKey: "public", mySecretKey: "secret", peerPublicKey: "peer"),
            label: machine, addedAt: now, lastCatalogAt: now, lastMachineName: machine
        )
    }

    private func session() -> SessionInfo {
        .init(sessionId: "claude", agent: "claude", projectId: "project", taskId: "task",
              computerId: "MacBook", title: "Pairing", cwd: "/repo", branch: "branch",
              worktree: "/repo", model: nil, summary: nil, accessLevel: nil, state: "idle",
              startedAt: now, lastActivityAt: now, tokensSession: 0, tokensLastTurn: 0)
    }

    private func render<Content: View>(_ view: Content) {
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.isHidden = false
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertNotNil(host.view.window)
        window.isHidden = true
        window.rootViewController = nil
    }
}
