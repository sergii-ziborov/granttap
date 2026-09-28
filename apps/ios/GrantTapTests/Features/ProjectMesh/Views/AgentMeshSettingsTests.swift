import XCTest
@testable import GrantTap

@MainActor
final class AgentMeshSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "granttap.agent-mesh.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testPreferencesDefaultToFourAgentsAndMeshThenRoundTrip() {
        var value = AgentMeshPreferencesStore.load(defaults: defaults)
        XCTAssertEqual(value.enabledProviders, Set(["claude", "codex", "cursor", "grok"]))
        XCTAssertTrue(value.meshEnabled)
        value.providerSettings["cursor"] = false
        value.meshEnabled = false
        AgentMeshPreferencesStore.save(value, defaults: defaults)
        let restored = AgentMeshPreferencesStore.load(defaults: defaults)
        XCTAssertFalse(restored.isProviderEnabled("cursor"))
        XCTAssertTrue(restored.isProviderEnabled("grok"))
        XCTAssertFalse(restored.meshEnabled)
        XCTAssertTrue(restored.isProviderEnabled("unknown"))
    }

    func testProviderDisablePreservesHistoryAndNeverResolvesPendingRequest() {
        let model = AppModel()
        model.agentMeshPreferences = .defaults
        model.sessions = [session(id: "live", agent: "cursor")]
        model.sessionHistory = [session(id: "history", agent: "cursor")]
        model.pending = [ApprovalRequest(
            type: "approval.request", requestId: "approval", agent: "cursor",
            kind: "permission", tool: "Shell", title: "Run tests",
            command: nil, cwd: nil, sessionId: "live", risk: .medium,
            danger: nil, createdAt: 1
        )]
        XCTAssertTrue(model.providerDisableRequiresConfirmation("cursor"))
        model.setProviderEnabled("cursor", enabled: false)
        XCTAssertEqual(model.sessions.map(\.sessionId), ["live"])
        XCTAssertEqual(model.sessionHistory.map(\.sessionId), ["history"])
        XCTAssertEqual(model.pending.map(\.requestId), ["approval"])
        XCTAssertTrue(model.approvalDecisionsInFlight.isEmpty)
        XCTAssertFalse(model.agentMeshPreferences.isProviderEnabled("cursor"))
    }

    func testMeshOffKeepsHistoryButRejectsNewEventsAndHandoffs() {
        let model = AppModel()
        model.meshSnapshots = ["project": snapshot()]
        model.pendingMeshEvents = []
        model.setProjectMeshEnabled(false)
        model.receive(event(), fromRoom: "room")
        XCTAssertEqual(model.meshSnapshots["project"]?.tasks.count, 1)
        XCTAssertTrue(model.pendingMeshEvents.isEmpty)
        model.prepareTaskHandoff(
            session: session(id: "source", agent: "claude", project: "project", task: "task"),
            targetProvider: "codex", targetComputer: "Workstation"
        )
        XCTAssertTrue(model.authorizedHandoffRoutes.isEmpty)
    }

    func testRoutePickerOnlyOffersEnabledCodingAgents() {
        let picker = TaskComposerRoutePicker(
            provider: .constant("claude"), computerId: .constant(nil),
            workspace: .constant(""), computers: [], workspaces: [],
            enabledProviders: ["claude", "grok"]
        )
        XCTAssertEqual(picker.providerIds, ["claude", "grok"])
    }

    private func session(
        id: String, agent: String, project: String? = nil, task: String? = nil
    ) -> SessionInfo {
        .init(sessionId: id, agent: agent, projectId: project, taskId: task,
              title: id, state: "idle", startedAt: 1, lastActivityAt: 1,
              tokensSession: 0, tokensLastTurn: 0)
    }

    private func snapshot() -> ProjectMeshSnapshot {
        ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "Project", repositoryRoot: "/repo",
                           canonicalRepositoryId: "repo", createdAt: 1),
            tasks: [.init(taskId: "task", projectId: "project", title: "Task", goal: "Goal",
                          state: "working", ownerSessionId: "source", createdAt: 1, updatedAt: 1)],
            executions: [], claims: [], dependencies: [], events: [], generatedAt: 1
        )
    }

    private func event() -> ProjectMeshEvent {
        ProjectMeshEvent(
            type: "mesh.event", sessionId: "task", eventId: "event", projectId: "project",
            taskId: "task", sourceSessionId: "source", eventType: "TASK_BLOCKED",
            createdAt: Date().timeIntervalSince1970 * 1_000,
            payload: .init(reason: "Blocked", needsUser: true)
        )
    }
}
