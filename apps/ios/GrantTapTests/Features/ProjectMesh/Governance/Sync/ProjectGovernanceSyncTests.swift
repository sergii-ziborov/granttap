import XCTest
@testable import GrantTap

@MainActor
final class ProjectGovernanceSyncTests: XCTestCase {
    private let now = 1_800_000_000_000.0

    func testWireValidatorRequiresBoundedExactProjectScope() throws {
        let status = ProjectGovernanceSyncFixtures.policyStatus(endpoint: "mac", provider: "claude", status: .enforced)
        let data = try JSONEncoder().encode(status)
        XCTAssertTrue(ProjectGovernanceWireValidator.validStatus(data))
        XCTAssertTrue(ProjectGovernanceWireValidator.validStatus(status))

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["unexpected"] = "plaintext"
        XCTAssertFalse(ProjectGovernanceWireValidator.validStatus(
            try JSONSerialization.data(withJSONObject: object)
        ))
        XCTAssertFalse(ProjectGovernanceWireValidator.validStatus(ProjectPolicyStatus(
            type: status.type, sessionId: "other", projectId: status.projectId,
            policy: status.policy, coverage: status.coverage, generatedAt: status.generatedAt
        )))

        let duplicate = ProjectPolicyAck(
            type: "project.policy.ack", sessionId: "project", projectId: "project",
            acknowledgement: .init(
                projectId: "project", policyRevision: 3, endpointId: "mac",
                provider: "claude",
                capabilities: [
                    .init(kind: .mcp, status: .enforced),
                    .init(kind: .mcp, status: .unknown),
                ], observedAt: now
            )
        )
        XCTAssertFalse(ProjectGovernanceWireValidator.validAck(duplicate))
        XCTAssertFalse(ProjectGovernanceWireValidator.validStatus(Data(repeating: 0, count: 65_537)))
    }

    func testSameRevisionCoverageConvergesAndStaleAckCannotChangeIt() {
        let first = ProjectGovernanceLogic.merged(
            current: nil,
            status: ProjectGovernanceSyncFixtures.policyStatus(endpoint: "mac", provider: "claude", status: .enforced)
        )
        let second = ProjectGovernanceLogic.merged(
            current: first,
            status: ProjectGovernanceSyncFixtures.policyStatus(endpoint: "pc", provider: "cursor", status: .unsupported)
        )
        XCTAssertEqual(second?.revision, 3)
        XCTAssertEqual(second?.coverage.map(\.endpointId).sorted(), ["mac", "pc"])
        XCTAssertEqual(second?.strictReady, false)

        let stale = ProjectPolicyAck(
            type: "project.policy.ack", sessionId: "project", projectId: "project",
            acknowledgement: .init(
                projectId: "project", policyRevision: 2, endpointId: "pc",
                provider: "cursor", capabilities: [.init(kind: .mcp, status: .enforced)],
                observedAt: now + 1
            )
        )
        XCTAssertEqual(ProjectGovernanceLogic.merged(current: second, ack: stale), second)

        var conflict = ProjectGovernanceSyncFixtures.policyStatus(endpoint: "other", provider: "codex", status: .enforced)
        conflict.policy.rules[0].effect = .allow
        XCTAssertEqual(ProjectGovernanceLogic.merged(current: second, status: conflict), second)
    }

    func testEditorRaisesOneRevisionAndPreservesCustomRules() throws {
        let current = ProjectGovernanceSyncFixtures.policyStatus(endpoint: "mac", provider: "claude", status: .enforced).policy
        let updated = ProjectGovernanceLogic.updatedPolicy(
            current: current, projectId: "project", enforcement: .bestAvailable,
            defaults: [.mcp: .deny, .shell: .ask], createdBy: "phone"
        )
        XCTAssertEqual(updated.revision, 4)
        XCTAssertTrue(updated.rules.allSatisfy { $0.revision == 4 })
        XCTAssertEqual(updated.rules.first(where: { $0.ruleId == "custom-release" })?.effect, .deny)
        XCTAssertEqual(updated.rules.first(where: {
            $0.ruleId == "granttap-default-mcp"
        })?.effect, .deny)
        XCTAssertEqual(updated.rules.first(where: {
            $0.ruleId == "granttap-default-shell"
        })?.effect, .ask)
        XCTAssertTrue(ProjectGovernanceWireValidator.validSet(ProjectPolicySet(
            type: "project.policy.set", sessionId: "project", projectId: "project",
            expectedRevision: 3, policy: updated, createdAt: now
        )))
    }

    func testSetWireAcceptsExactFingerprintAndRejectsPoisonedNestedShapes() throws {
        let hash = String(repeating: "a", count: 64)
        let fingerprint = ProjectCapabilityFingerprint(
            kind: .mcp, displayName: "GitHub", provider: "claude", origin: "catalog",
            publisher: "GitHub", version: "1", transport: "stdio",
            executablePathHash: hash, confidence: .exact
        )
        let rule = ProjectPolicyRule(
            ruleId: "exact-github", projectId: "project",
            selector: ProjectPolicySelector(
                kind: .mcp, displayName: "GitHub", provider: "claude", origin: "catalog",
                fingerprint: ProjectFingerprintPredicate(match: .exact, expected: fingerprint)
            ), effect: .allow,
            conditions: ProjectPolicyConditions(
                endpointIds: ["mac"], providers: ["claude"], impact: "available"
            ), revision: 1, createdBy: "phone"
        )
        let request = ProjectPolicySet(
            type: "project.policy.set", sessionId: "project", projectId: "project",
            expectedRevision: 0,
            policy: ProjectPolicy(
                projectId: "project", revision: 1, enforcement: .bestAvailable,
                rules: [rule]
            ), createdAt: now
        )
        let data = try JSONEncoder().encode(request)
        XCTAssertTrue(ProjectGovernanceWireValidator.validSet(data))
        XCTAssertEqual(ProjectCapabilityKind.mcp.id, "mcp")
        XCTAssertEqual(rule.id, "exact-github")

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var policy = try XCTUnwrap(object["policy"] as? [String: Any])
        var rules = try XCTUnwrap(policy["rules"] as? [[String: Any]])
        var selector = try XCTUnwrap(rules[0]["selector"] as? [String: Any])
        var predicate = try XCTUnwrap(selector["fingerprint"] as? [String: Any])
        predicate["unexpected"] = true
        selector["fingerprint"] = predicate
        rules[0]["selector"] = selector
        policy["rules"] = rules
        object["policy"] = policy
        XCTAssertFalse(ProjectGovernanceWireValidator.validSet(
            try JSONSerialization.data(withJSONObject: object)
        ))

        var weak = fingerprint
        weak = ProjectCapabilityFingerprint(
            kind: weak.kind, displayName: weak.displayName,
            executablePathHash: weak.executablePathHash, confidence: .strong
        )
        var weakRule = rule
        weakRule.selector.fingerprint = ProjectFingerprintPredicate(
            match: .changedFrom, expected: weak
        )
        let weakPolicy = ProjectPolicy(
            projectId: "project", revision: 1, enforcement: .bestAvailable, rules: [weakRule]
        )
        XCTAssertFalse(ProjectGovernanceWireValidator.validSet(ProjectPolicySet(
            type: request.type, sessionId: request.sessionId, projectId: request.projectId,
            expectedRevision: 0, policy: weakPolicy, createdAt: now
        )))
        weakRule.selector.fingerprint = ProjectFingerprintPredicate(
            match: .confidence, value: .unknown
        )
        XCTAssertTrue(ProjectGovernanceWireValidator.validSet(ProjectPolicySet(
            type: request.type, sessionId: request.sessionId, projectId: request.projectId,
            expectedRevision: 0,
            policy: ProjectPolicy(
                projectId: "project", revision: 1, enforcement: .bestAvailable,
                rules: [weakRule]
            ), createdAt: now
        )))
    }
}
