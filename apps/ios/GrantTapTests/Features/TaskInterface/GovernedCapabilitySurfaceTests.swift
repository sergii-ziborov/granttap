import SwiftUI
import XCTest
@testable import GrantTap

/// The surfaces that report Project policy instead of switching it.
///
/// Each one has a branch that only appears with real data behind it — a Project
/// that governs, a paired computer that is absent, a provider that accepts an
/// effort flag — so they are rendered with that data rather than an empty model.
@MainActor
final class GovernedCapabilitySurfaceTests: XCTestCase {
    private func session(agent: String) -> SessionInfo {
        SessionInfo(
            sessionId: "chat", agent: agent, projectId: "project", title: "Governed",
            cwd: "/repo", model: "opus", accessLevel: "workspace", state: "working",
            startedAt: 1, lastActivityAt: 2, tokensSession: 1, tokensLastTurn: 1
        )
    }

    private func rows() -> [ChatCapabilityRow] {
        [
            ChatCapabilityRow(kind: .mcp, name: "github", allowed: true,
                              calls: 4, tokens: 90, needsAuth: false),
            ChatCapabilityRow(kind: .skill, name: "review", allowed: true,
                              calls: 1, tokens: 5, needsAuth: false),
            ChatCapabilityRow(kind: .cli, name: "shell", allowed: false,
                              calls: 0, tokens: 0, needsAuth: false),
        ]
    }

    private func snapshot(bound: [String]) -> ProjectMeshSnapshot {
        let bindings = bound.map { endpoint in
            ProjectBindingSummary(
                bindingId: "binding-\(endpoint)", projectId: "project", endpointId: endpoint,
                repositoryId: "repo", displayName: endpoint, available: true
            )
        }
        return .init(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "GrantTap", repositoryRoot: "/repo",
                           canonicalRepositoryId: "repo", createdAt: 1),
            bindings: bindings,
            tasks: [], executions: [], claims: [], dependencies: [], events: [],
            generatedAt: 1
        )
    }

    /// A Project that governs MCP strictly, skills by asking and scripts by deny.
    private func governed(_ model: AppModel) {
        let effects: [ProjectCapabilityKind: ProjectPolicyEffect] = [
            .mcp: .allow, .skill: .ask, .shell: .allow, .script: .deny,
        ]
        let rules = effects.map { kind, effect in
            ProjectPolicyRule(
                ruleId: "granttap-default-\(kind.rawValue)", projectId: "project",
                selector: ProjectPolicySelector(kind: kind), effect: effect,
                conditions: ProjectPolicyConditions(endpointIds: [], providers: []),
                revision: 2, createdBy: "phone"
            )
        }
        let status = ProjectPolicyStatus(
            type: "project.policy.status", sessionId: "project", projectId: "project",
            policy: ProjectPolicy(
                projectId: "project", revision: 2, enforcement: .bestAvailable, rules: rules
            ),
            coverage: ProjectPolicyCoverage(
                projectId: "project", policyRevision: 2, enforcement: .bestAvailable,
                requiredCapabilities: [], endpoints: [], strictReady: false
            ), generatedAt: 1_800_000_000_000
        )
        model.projectGovernance["project"] = ProjectGovernanceLogic.merged(
            current: nil, status: status
        )
    }

    func testAGovernedTaskReportsPolicyAndRoutesToGovernance() throws {
        let model = AppModel()
        governed(model)
        model.meshSnapshots["project"] = snapshot(bound: ["mac"])
        let projection = try XCTUnwrap(model.projectGovernance["project"])

        assertRendered(ChatGovernedCapabilitySection(
            rows: rows(), snapshot: snapshot(bound: ["mac"]),
            projection: projection, model: model
        ).environmentObject(model))

        // A denied script outranks an allowed shell on the one row that covers both.
        XCTAssertEqual(ChatCapabilityGovernance.effect(for: .cli, in: projection), .deny)
        XCTAssertEqual(ChatCapabilityGovernance.effect(for: .skill, in: projection), .ask)
    }

    func testTheTaskSheetSwapsSwitchesForPolicyOnceAProjectGoverns() {
        let model = AppModel()
        model.meshSnapshots["project"] = snapshot(bound: ["mac"])
        let sheet = ChatCapabilitySheet(
            sessionId: "chat", session: session(agent: "claude"), rows: rows(),
            accent: .blue, model: model, onToggle: { _ in }
        )
        // Ungoverned first: the switches are still the only thing deciding.
        assertRendered(sheet.environmentObject(model))
        governed(model)
        assertRendered(sheet.environmentObject(model))
    }

    func testEffortIsOfferedToClaudeAndWithheldFromCodex() {
        let model = AppModel()
        let claude = ChatTurnOverridesSection(
            sessionId: "chat", agent: "claude", model: model
        )
        assertRendered(claude.environmentObject(model))

        var picked = model.turnOverrides.chatOverrides("chat")
        picked.effort = .xhigh
        picked.model = .opus
        model.turnOverrides.setChatOverrides(picked, for: "chat")
        assertRendered(claude.environmentObject(model))
        XCTAssertEqual(model.turnOverrides.chatOverrides("chat").effort, .xhigh)

        // Codex takes a model alias but no effort, and grok takes neither, so the
        // section renders with one picker and then with none at all.
        assertRendered(
            ChatTurnOverridesSection(sessionId: "chat", agent: "codex", model: model)
                .environmentObject(model)
        )
        assertRendered(
            ChatTurnOverridesSection(sessionId: "chat", agent: "grok", model: model)
                .environmentObject(model)
        )

        // Picking through the section itself, which is what the pickers do.
        claude.modelBinding.wrappedValue = .sonnet
        claude.effortBinding.wrappedValue = .low
        XCTAssertEqual(model.turnOverrides.chatOverrides("chat").model, .sonnet)
        XCTAssertEqual(model.turnOverrides.chatOverrides("chat").effort, .low)
        XCTAssertEqual(claude.modelBinding.wrappedValue, .sonnet)
        XCTAssertEqual(claude.effortBinding.wrappedValue, .low)

        // Clearing returns the chat to whatever the agent-wide default says.
        claude.modelBinding.wrappedValue = nil
        claude.effortBinding.wrappedValue = nil
        XCTAssertNil(model.turnOverrides.chatOverrides("chat").model)
        XCTAssertNil(model.turnOverrides.chatOverrides("chat").effort)
    }

    func testMembersNamesBoundAndAbsentComputers() {
        let model = AppModel()
        let pairing = Pairing(
            relayUrl: "wss://relay.granttap.ai", room: "air", role: "phone",
            deviceName: "Air", senderId: "phone", myPublicKey: "a",
            mySecretKey: "b", peerPublicKey: "c", pushAuth: "d"
        )
        model.connectionRegistry = .init(
            connections: [LinkedComputer(
                id: "air", pairing: pairing, label: "Air", addedAt: 1,
                lastCatalogAt: 1, lastMachineName: "Air"
            )],
            preferredId: "air"
        )
        // One computer reports the Project and one paired computer does not.
        assertRendered(
            ProjectMembersView(snapshot: snapshot(bound: ["mac"]), model: model)
                .environmentObject(model)
        )
        // Then the absent one joins, and there is nothing left to explain.
        assertRendered(
            ProjectMembersView(snapshot: snapshot(bound: ["air"]), model: model)
                .environmentObject(model)
        )
        // A Project no computer has reported at all: nothing holds the mesh key,
        // so the add action is present but refused.
        assertRendered(
            ProjectMembersView(snapshot: snapshot(bound: []), model: model)
                .environmentObject(model)
        )
        XCTAssertFalse(model.admitComputerToProject(projectId: "project", room: "air"))

        // With a participant holding the key, the row offers a real grant.
        model.meshProjectSourceRooms["project"] = ["mac"]
        model.meshSnapshots["project"] = snapshot(bound: ["mac"])
        assertRendered(
            ProjectMembersView(snapshot: snapshot(bound: ["mac"]), model: model)
                .environmentObject(model)
        )
        XCTAssertTrue(ProjectMeshAdmission.canAdmit(
            target: "air", participating: ["mac"],
            paired: model.connectionRegistry.connections
        ))
    }

    private func assertRendered<V: View>(_ view: V) {
        let frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: frame)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = frame
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}
