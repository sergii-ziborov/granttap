@testable import GrantTap

enum ProjectGovernanceFixtures {
    static func status(
        projectId: String = "project", revision: Int = 3,
        endpoint: String = "mac", provider: String = "claude"
    ) -> ProjectPolicyStatus {
        let policy = ProjectPolicy(
            projectId: projectId, revision: revision, enforcement: .strict,
            rules: [ProjectPolicyRule(
                ruleId: "granttap-default-mcp", projectId: projectId,
                selector: ProjectPolicySelector(kind: .mcp), effect: .ask,
                conditions: ProjectPolicyConditions(endpointIds: [], providers: []),
                revision: revision, createdBy: "phone"
            )]
        )
        let acknowledgement = ProjectPolicyAcknowledgement(
            projectId: projectId, policyRevision: revision, endpointId: endpoint,
            provider: provider,
            capabilities: [ProjectCapabilityCoverage(kind: .mcp, status: .enforced)],
            observedAt: 1_800_000_000_000
        )
        return ProjectPolicyStatus(
            type: "project.policy.status", sessionId: projectId, projectId: projectId,
            policy: policy,
            coverage: ProjectPolicyCoverage(
                projectId: projectId, policyRevision: revision, enforcement: .strict,
                requiredCapabilities: [.mcp], endpoints: [acknowledgement], strictReady: true
            ), generatedAt: 1_800_000_000_000
        )
    }

    static func acknowledgement(
        projectId: String = "project", revision: Int = 3,
        endpoint: String = "mac", provider: String = "claude"
    ) -> ProjectPolicyAck {
        let status = status(
            projectId: projectId, revision: revision, endpoint: endpoint, provider: provider
        )
        return ProjectPolicyAck(
            type: "project.policy.ack", sessionId: projectId, projectId: projectId,
            acknowledgement: status.coverage.endpoints[0]
        )
    }
}
