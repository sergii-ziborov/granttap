import SwiftUI
import XCTest
@testable import GrantTap

/// Forbidding one server without forbidding every server.
final class ProjectGovernanceNamedTests: XCTestCase {
    private func policy(_ rules: [ProjectPolicyRule], revision: Int = 2) -> ProjectPolicy {
        ProjectPolicy(
            projectId: "project", revision: revision, enforcement: .bestAvailable, rules: rules
        )
    }

    func testANamedRuleIsNarrowerThanItsKind() {
        let updated = ProjectGovernanceLogic.updatedPolicy(
            current: policy([]), projectId: "project", enforcement: .bestAvailable,
            defaults: [.mcp: .allow],
            named: [.init(kind: .mcp, name: "github"): .deny],
            createdBy: "phone"
        )
        let named = updated.rules.first { $0.selector.displayName == "github" }
        XCTAssertEqual(named?.effect, .deny)
        XCTAssertEqual(named?.selector.kind, .mcp)
        // The kind default is untouched: everything else stays allowed.
        XCTAssertEqual(
            updated.rules.first { $0.ruleId == "granttap-default-mcp" }?.effect, .allow
        )
    }

    func testEditingANamedRuleReplacesItRatherThanStacking() {
        let first = ProjectGovernanceLogic.updatedPolicy(
            current: nil, projectId: "project", enforcement: .bestAvailable,
            defaults: [:], named: [.init(kind: .mcp, name: "github"): .ask],
            createdBy: "phone"
        )
        let second = ProjectGovernanceLogic.updatedPolicy(
            current: first, projectId: "project", enforcement: .bestAvailable,
            defaults: [:], named: [.init(kind: .mcp, name: "github"): .deny],
            createdBy: "phone"
        )
        let matching = second.rules.filter { $0.selector.displayName == "github" }
        XCTAssertEqual(matching.count, 1, "an edit replaces, it does not stack")
        XCTAssertEqual(matching.first?.effect, .deny)
    }

    func testOneNameUnderTwoKindsStaysTwoDecisions() {
        let updated = ProjectGovernanceLogic.updatedPolicy(
            current: nil, projectId: "project", enforcement: .bestAvailable, defaults: [:],
            named: [
                .init(kind: .mcp, name: "review"): .deny,
                .init(kind: .skill, name: "review"): .allow,
            ], createdBy: "phone"
        )
        XCTAssertEqual(updated.rules.filter { $0.selector.displayName == "review" }.count, 2)
    }

    func testNamedRulesRoundTripBackIntoTheEditor() {
        let updated = ProjectGovernanceLogic.updatedPolicy(
            current: nil, projectId: "project", enforcement: .strict, defaults: [.shell: .ask],
            named: [.init(kind: .shell, name: "rm"): .deny], createdBy: "phone"
        )
        let read = ProjectGovernanceLogic.namedEffects(updated)
        XCTAssertEqual(read[.init(kind: .shell, name: "rm")], .deny)
        // Kind defaults are not named rules and must not leak into them.
        XCTAssertEqual(read.count, 1)
    }

    func testCandidatesAreWhatTheProjectUsedPlusWhatItAlreadyDecided() {
        let used = CapabilityUsageEvent(
            id: "1", sourceId: "room:1", kind: .cli, name: "bash",
            sessionId: "mine", createdAt: 1, toolName: "bash"
        )
        let elsewhere = CapabilityUsageEvent(
            id: "2", sourceId: "room:2", kind: .mcp, name: "other-project-server",
            sessionId: "theirs", createdAt: 1, toolName: "x"
        )
        let candidates = ProjectGovernanceCandidates.named(
            events: [used, elsewhere], sessionIds: ["mine"],
            existing: [.init(kind: .mcp, name: "github"): .deny]
        )
        // A shell call is offered under the kind the Project can act on.
        XCTAssertTrue(candidates.contains(.init(kind: .shell, name: "bash")))
        // A rule already written is offered even though nothing ran lately.
        XCTAssertTrue(candidates.contains(.init(kind: .mcp, name: "github")))
        // Another task's capability is not this Project's business.
        XCTAssertFalse(candidates.contains(.init(kind: .mcp, name: "other-project-server")))

        // A server the Project is configured with is offered before it has ever
        // been called: a rule that can only be written after the thing it
        // forbids has already run is not a rule anyone can rely on.
        let withConfigured = ProjectGovernanceCandidates.named(
            events: [used, elsewhere], sessionIds: ["mine"],
            existing: [.init(kind: .mcp, name: "github"): .deny],
            configured: ["granttap", "github"]
        )
        XCTAssertTrue(withConfigured.contains(.init(kind: .mcp, name: "granttap")))
        // Configuring something already decided does not offer it twice.
        XCTAssertEqual(
            withConfigured.filter { $0 == .init(kind: .mcp, name: "github") }.count, 1
        )
    }

    /// The section is the only place a named rule can be chosen, so it is laid
    /// out for real rather than only its logic exercised.
    @MainActor
    func testTheSectionRendersAndPicksThrough() {
        var named: [ProjectGovernanceLogic.NamedRule: ProjectPolicyEffect] = [:]
        let candidates: [ProjectGovernanceLogic.NamedRule] = [
            .init(kind: .mcp, name: "github"),
            .init(kind: .shell, name: "bash"),
        ]
        let binding = Binding(get: { named }, set: { named = $0 })
        RenderProbe.render(
            List {
                ProjectGovernanceNamedSection(
                    candidates: candidates, named: binding, enabled: true
                )
            }
        )
        // Nothing to decide draws nothing rather than an empty header.
        RenderProbe.render(
            List {
                ProjectGovernanceNamedSection(candidates: [], named: binding, enabled: false)
            }
        )

        named[.init(kind: .mcp, name: "github")] = .deny
        RenderProbe.render(
            List {
                ProjectGovernanceNamedSection(
                    candidates: candidates, named: binding, enabled: true
                )
            }
        )
        XCTAssertEqual(named[.init(kind: .mcp, name: "github")], .deny)
    }

    /// The Governance screen is where every rule is actually chosen, so it is
    /// laid out against a Project that reports one.
    @MainActor
    func testGovernanceScreenRendersGovernedAndUngoverned() {
        let model = AppModel()
        let projectId = "gov-\(UUID().uuidString)"
        let project = ProjectMeshProject(
            projectId: projectId, name: "GrantTap", repositoryRoot: "/repo",
            canonicalRepositoryId: "repo", createdAt: 1
        )
        let mesh = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: projectId, projectId: projectId,
            project: project, tasks: [], executions: [], claims: [],
            dependencies: [], events: [], generatedAt: 1
        )
        model.meshSnapshots[projectId] = mesh

        // Nothing reported: the screen says so instead of showing an editor.
        RenderProbe.render(NavigationView {
            ProjectGovernanceView(project: project, model: model)
        })

        let status = ProjectPolicyStatus(
            type: "project.policy.status", sessionId: projectId, projectId: projectId,
            policy: ProjectGovernanceLogic.updatedPolicy(
                current: nil, projectId: projectId, enforcement: .strict,
                defaults: [.mcp: .ask, .shell: .allow],
                named: [.init(kind: .mcp, name: "github"): .deny], createdBy: "phone"
            ),
            coverage: ProjectPolicyCoverage(
                projectId: projectId, policyRevision: 1, enforcement: .strict,
                requiredCapabilities: [.mcp], endpoints: [], strictReady: false
            ), generatedAt: 1_800_000_000_000
        )
        model.projectGovernance[projectId] = ProjectGovernanceLogic.merged(
            current: nil, status: status
        )
        RenderProbe.render(NavigationView {
            ProjectGovernanceView(project: project, model: model)
        })

        // Editing without a computer to deliver to is refused, and says why.
        XCTAssertFalse(model.applyProjectGovernance(
            projectId: projectId, enforcement: .bestAvailable,
            defaults: [.mcp: .deny], named: [:]
        ))
        XCTAssertNotNil(model.projectPolicyErrors[projectId])
    }
}

extension ProjectGovernanceNamedTests {
    func testACellTogglesAndATypedNameBecomesARow() {
        XCTAssertEqual(ProjectGovernanceTable.toggled(current: nil, tapped: .deny), .deny)
        XCTAssertEqual(ProjectGovernanceTable.toggled(current: .deny, tapped: .ask), .ask)
        XCTAssertNil(ProjectGovernanceTable.toggled(current: .ask, tapped: .ask), "tapping the chosen cell clears it")
        XCTAssertEqual(ProjectGovernanceTable.customRule(.shell, name: "  rm "), .init(kind: .shell, name: "rm"))
        XCTAssertNil(ProjectGovernanceTable.customRule(.shell, name: "   "))
        XCTAssertNil(ProjectGovernanceTable.customRule(.shell, name: "two\nlines"))
        XCTAssertNil(ProjectGovernanceTable.customRule(.shell, name: String(repeating: "x", count: 161)))
        for kind in ProjectCapabilityKind.allCases {
            XCTAssertFalse(ProjectGovernanceTable.kindTitle(kind).isEmpty)
            XCTAssertFalse(ProjectGovernanceTable.placeholder(kind).isEmpty)
        }
    }

    func testEveryProviderToolIsARowAndAScriptIsOfferedAsAScript() {
        let event = CapabilityUsageEvent(
            id: "e", sourceId: "s", agent: "claude", model: "m", kind: .cli, name: "check.sh",
            sessionId: "chat", createdAt: 1, toolName: "Bash", durationMs: 1, outcome: .success
        )
        let rows = ProjectGovernanceCandidates.named(
            events: [event], sessionIds: ["chat"], existing: [:], extra: ProjectGovernanceCandidates.builtIn
        )
        XCTAssertTrue(rows.contains(.init(kind: .script, name: "check.sh")))
        XCTAssertFalse(rows.contains(.init(kind: .shell, name: "check.sh")))
        XCTAssertTrue(rows.contains(.init(kind: .fileWrite, name: "Write")))
        XCTAssertTrue(rows.contains(.init(kind: .network, name: "WebFetch")))
        XCTAssertTrue(rows.contains(.init(kind: .deploy, name: "git push")), "forbidding a push is a row, not a whole kind")
        XCTAssertTrue(rows.contains(.init(kind: .shell, name: "rm")))
        XCTAssertEqual(ProjectGovernanceCandidates.governedKind(.cli), .shell)
        XCTAssertEqual(ProjectGovernanceCandidates.governedKind(.cli, name: "build.py"), .script)
        XCTAssertEqual(ProjectGovernanceCandidates.governedKind(.mcp, name: "x"), .mcp)
        XCTAssertEqual(ProjectGovernanceCandidates.governedKind(.skill, name: "x"), .skill)
    }

    @MainActor
    func testTheTableRendersEveryKindWithItsAddRow() {
        var named: [ProjectGovernanceLogic.NamedRule: ProjectPolicyEffect] = [.init(kind: .shell, name: "rm"): .deny]
        var custom: Set<ProjectGovernanceLogic.NamedRule> = [.init(kind: .shell, name: "rm")]
        let namedBinding = Binding(get: { named }, set: { named = $0 })
        let customBinding = Binding(get: { custom }, set: { custom = $0 })
        let candidates = ProjectGovernanceCandidates.named(
            events: [], sessionIds: [], existing: named, configured: ["github"],
            extra: ProjectGovernanceCandidates.builtIn + Array(custom)
        )
        RenderProbe.render(
            List {
                ProjectGovernanceNamedSection(
                    candidates: candidates, named: namedBinding, enabled: true, customNames: customBinding
                )
            }
        )
        RenderProbe.render(ProjectGovernanceEffectCells(selected: .allow, enabled: true) { _ in })
        RenderProbe.render(ProjectGovernanceEffectCells(selected: nil, enabled: false) { _ in })
    }
}
