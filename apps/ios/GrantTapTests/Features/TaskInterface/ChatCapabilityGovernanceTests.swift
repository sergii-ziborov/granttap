import XCTest
@testable import GrantTap

final class ChatCapabilityGovernanceTests: XCTestCase {
    private func projection(
        _ effects: [ProjectCapabilityKind: ProjectPolicyEffect]
    ) -> ProjectGovernanceProjection? {
        let rules = effects.map { kind, effect in
            ProjectPolicyRule(
                ruleId: "granttap-default-\(kind.rawValue)", projectId: "project",
                selector: ProjectPolicySelector(kind: kind), effect: effect,
                conditions: ProjectPolicyConditions(endpointIds: [], providers: []),
                revision: 4, createdBy: "phone"
            )
        }
        let status = ProjectPolicyStatus(
            type: "project.policy.status", sessionId: "project", projectId: "project",
            policy: ProjectPolicy(
                projectId: "project", revision: 4, enforcement: .bestAvailable, rules: rules
            ),
            coverage: ProjectPolicyCoverage(
                projectId: "project", policyRevision: 4, enforcement: .bestAvailable,
                requiredCapabilities: [], endpoints: [], strictReady: false
            ), generatedAt: 1_800_000_000_000
        )
        return ProjectGovernanceLogic.merged(current: nil, status: status)
    }

    func testShellRowIsGovernedByBothShellAndScript() {
        // "Bash" is not one permission: typing a command and running a script
        // are governed separately, and the chat meets whichever is stricter.
        XCTAssertEqual(
            Set(ChatCapabilityGovernance.governing(.cli)), Set([.shell, .script])
        )
        XCTAssertEqual(ChatCapabilityGovernance.governing(.mcp), [.mcp])
        XCTAssertEqual(ChatCapabilityGovernance.governing(.skill), [.skill])
    }

    func testStricterOfShellAndScriptWins() {
        XCTAssertEqual(
            ChatCapabilityGovernance.effect(
                for: .cli, in: projection([.shell: .allow, .script: .deny])
            ), .deny
        )
        XCTAssertEqual(
            ChatCapabilityGovernance.effect(
                for: .cli, in: projection([.shell: .ask, .script: .allow])
            ), .ask
        )
    }

    func testUngovernedCapabilityReportsNothingRatherThanGuessing() {
        XCTAssertNil(ChatCapabilityGovernance.effect(for: .mcp, in: nil))
        // A Project that governs only the shell says nothing about MCP.
        XCTAssertNil(
            ChatCapabilityGovernance.effect(for: .mcp, in: projection([.shell: .deny]))
        )
        XCTAssertEqual(
            ChatCapabilityGovernance.effect(for: .skill, in: projection([.skill: .ask])), .ask
        )
    }
}
