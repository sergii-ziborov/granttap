import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class AgentsMeshSurfaceCoverageTests: XCTestCase {
    override func setUp() {
        super.setUp()
        GrokBotEndpointStore.remove()
        AgentMeshPreferencesStore.save(.defaults)
    }

    override func tearDown() {
        GrokBotEndpointStore.remove()
        AgentMeshPreferencesStore.save(.defaults)
        super.tearDown()
    }

    func testSettingsRenderDisconnectedConnectedAndInviteStates() {
        let model = AppModel()
        model.agentMeshPreferences = .defaults
        model.meshSnapshots = ["project": snapshot()]

        render(CompatNavigationStack { List { AgentsMeshSettingsSection(model: model) } })
        render(GrokBotSettingsView(model: model))

        let section = AgentsMeshSettingsSection(model: model)
        XCTAssertEqual(section.grokBotStatus, "Not connected")
        section.providerBinding("cursor").wrappedValue = false
        XCTAssertFalse(model.agentMeshPreferences.isProviderEnabled("cursor"))
        section.providerBinding("cursor").wrappedValue = true
        section.meshBinding.wrappedValue = false
        XCTAssertFalse(model.agentMeshPreferences.meshEnabled)

        model.grokBotConnection = connection(status: "pending")
        XCTAssertEqual(section.grokBotStatus, "Connecting")
        render(GrokBotSettingsView(model: model))
        model.grokBotConnection?.endpoint.status = "active"
        XCTAssertEqual(section.grokBotStatus, "Connected")
        render(GrokBotSettingsView(model: model))

        let settings = GrokBotSettingsView(model: model)
        XCTAssertEqual(settings.activeConnection?.endpoint.endpointId, "endpoint")
        settings.actorBinding("qa-bot").wrappedValue = false
        XCTAssertFalse(model.grokBotConnection?.actors[0].enabled == true)
        XCTAssertFalse(settings.actorBinding("missing").wrappedValue)

        let invite = GrokBotInviteView(model: model)
        XCTAssertEqual(invite.projects.map(\.projectId), ["project"])
        invite.projectBinding("project").wrappedValue = true
        invite.projectBinding("project").wrappedValue = false
        render(invite)
        render(GrokBotInviteView(
            model: model, issuedInvite: "granttap-mesh://invite/one-time", failure: "Relay unavailable"
        ))

        model.sessions = [session(id: "live", provider: "codex")]
        model.pending = [approval(provider: "codex")]
        XCTAssertTrue(model.providerDisableRequiresConfirmation("codex"))
        section.providerBinding("codex").wrappedValue = false
        XCTAssertTrue(model.agentMeshPreferences.isProviderEnabled("codex"))
        render(CompatNavigationStack {
            List { AgentsMeshSettingsSection(model: model, pendingDisable: "codex") }
        })
    }

    func testInviteGenerationFailureAndProviderConfirmationBranches() async {
        let model = AppModel()
        model.agentMeshPreferences = .defaults
        model.meshSnapshots = ["project": snapshot()]
        let invite = GrokBotInviteView(model: model)
        invite.projectBinding("project").wrappedValue = true
        invite.generate()
        await Task.yield()
        try? await Task.sleep(nanoseconds: 30_000_000)

        model.sessions = [session(id: "live", provider: "claude")]
        model.sessionHistory = [session(id: "history", provider: "codex")]
        model.archivedSessions = ["archived": session(id: "archived", provider: "cursor")]
        model.questions = [question(sessionId: "history")]
        XCTAssertTrue(model.providerDisableRequiresConfirmation("codex"))
        model.questions = [question(sessionId: "missing")]
        XCTAssertFalse(model.providerDisableRequiresConfirmation("codex"))

        model.pending = [approval(provider: "claude")]
        XCTAssertTrue(model.providerDisableRequiresConfirmation("claude"))
        model.pending = []
        model.meshSnapshots = ["project": handoffSnapshot(resolved: false)]
        XCTAssertTrue(model.providerDisableRequiresConfirmation("cursor"))
        model.meshSnapshots = ["project": handoffSnapshot(resolved: true)]
        XCTAssertFalse(model.providerDisableRequiresConfirmation("cursor"))
        model.setProviderEnabled("copilot", enabled: false)
        XCTAssertTrue(model.agentMeshPreferences.isProviderEnabled("unknown"))
    }

    func testGrokActorPolicyConnectionAndRevocationLifecycle() {
        let model = AppModel()
        model.agentMeshPreferences = .init(
            providerSettings: AgentMeshPreferences.defaults.providerSettings,
            meshEnabled: false
        )
        model.grokBotConnection = connection(status: "active")
        model.meshSnapshots = ["project": snapshotWithGrokClaim()]

        model.startGrokBotEndpointIfNeeded()
        model.meshEndpointRelaysById.values.forEach { $0.disconnect() }
        model.meshEndpointRelaysById.removeAll()
        model.setGrokBotActorEnabled("missing", enabled: false)
        model.setGrokBotActorEnabled("qa-bot", enabled: false)
        XCTAssertTrue(model.meshSnapshots["project"]?.claims.isEmpty == true)
        XCTAssertGreaterThan(model.grokBotConnection?.policy.revision ?? 0, 1)
        model.setGrokBotActorEnabled("qa-bot", enabled: true)

        let client = RelayClient(pairing: pairing(room: "bot-room"))
        model.meshEndpointRelaysById["endpoint"] = client
        model.noteGrokBotConnection(false, endpointId: "wrong", client: client)
        model.noteGrokBotConnection(false, endpointId: "endpoint", client: client)
        XCTAssertEqual(model.grokBotConnection?.endpoint.status, "pending")
        model.noteGrokBotConnection(true, endpointId: "endpoint", client: client)
        XCTAssertEqual(model.grokBotConnection?.endpoint.status, "active")

        model.revokeGrokBotConnection()
        XCTAssertEqual(model.grokBotConnection?.credential.status, "revoked")
        XCTAssertEqual(model.grokBotConnection?.endpoint.status, "revoked")
        model.revokeGrokBotConnection()
        client.disconnect()
    }

    func testHandoffRendersCodingAndGrokDestinations() {
        let model = AppModel()
        model.agentMeshPreferences = .defaults
        let source = linked(room: "source", machine: "MacBook")
        let target = linked(room: "target", machine: "")
        model.connectionRegistry = .init(connections: [source, target], preferredId: source.id)
        model.sessionSourceRooms["source-session"] = [source.id]
        model.grokBotConnection = connection(status: "active")

        let sourceSession = session(
            id: "source-session", provider: "claude", projectId: "project", taskId: "task"
        )
        // A handoff is only offered for a task whose computer published a live,
        // readable checkout for the owning execution.
        var state = snapshot()
        state.executions = [.init(taskId: "task", sessionId: "source-session", provider: "claude",
                                  computerId: "MacBook", workspace: "/repo", uncommitted: false,
                                  updatedAt: 1, startedAt: 1)]
        model.meshSnapshots = ["project": state]
        let sheet = TaskHandoffSheet(session: sourceSession, model: model)
        XCTAssertEqual(sheet.grokActors.map(\.displayName), ["QA Bot", "Research Bot"])
        XCTAssertEqual(sheet.defaultSelection.provider, "codex")
        XCTAssertEqual(sheet.computerName(target), target.displayName)
        _ = sheet.computerOptions
        _ = sheet.agentOptions
        render(sheet)
        XCTAssertFalse(sheet.performHandoff(targetRoom: "missing", targetProvider: "codex"))
        XCTAssertFalse(sheet.performHandoff(targetRoom: target.id, targetProvider: "copilot"))
        XCTAssertTrue(sheet.performHandoff(targetRoom: target.id, targetProvider: "codex"))
    }

    func testGrokEndpointAcceptsScopedProgressAndActorHandoff() {
        let model = AppModel()
        model.agentMeshPreferences = .defaults
        model.grokBotConnection = connection(status: "active")
        model.meshSnapshots = ["project": snapshot()]
        let source = RelayClient(pairing: pairing(room: "source-room"))
        model.relaysByRoom["source-room"] = source
        model.sessionSourceRooms["source-session"] = ["source-room"]
        model.meshProjectSourceRooms["project"] = ["source-room"]
        _ = source.installForwardedScopeKey(
            Data(repeating: 7, count: 32).base64EncodedString(), scopeId: "project"
        )
        model.attachGrokBotEndpoint(model.grokBotConnection!)
        let bot = model.meshEndpointRelaysById["endpoint"]!
        model.noteGrokBotConnection(true, endpointId: "endpoint", client: bot)

        let sourceSession = session(
            id: "source-session", provider: "claude", projectId: "project", taskId: "task"
        )
        model.prepareTaskHandoff(session: sourceSession, targetActorId: "missing")
        model.prepareTaskHandoff(session: sourceSession, targetActorId: "qa-bot")
        let progress = ProjectMeshEvent(
            type: "mesh.event", sessionId: "task", eventId: "bot-progress",
            projectId: "project", taskId: "task", sourceSessionId: "actor:qa-bot",
            sourceActorId: "qa-bot", eventType: "TASK_PROGRESS", createdAt: 2,
            payload: .init(summary: "Regression verified")
        )
        bot.onMeshEvent?(progress)
        XCTAssertTrue(model.meshSnapshots["project"]?.events.contains(progress) == true)
        model.meshEndpointRelaysById.values.forEach { $0.disconnect() }
        source.disconnect()
    }

    private func render<Content: View>(_ view: Content) {
        // A visible window is what makes SwiftUI build lazy List/ForEach rows.
        // Without one the section shell renders and every row closure is skipped.
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.isHidden = false
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertGreaterThan(host.sizeThatFits(in: host.view.bounds.size).height, 0)
        window.isHidden = true
        window.rootViewController = nil
    }
}
