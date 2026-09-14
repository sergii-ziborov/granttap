import XCTest
@testable import GrantTap

/// The pieces a Governance test builds on: a policy status as a computer
/// reports it, and the Project the editor opens against.
@MainActor
enum ProjectGovernanceSyncFixtures {
    static let now = 1_800_000_000_000.0

    /// The Project as the mesh names it, for opening the editor in a test.
    static func projectSnapshotProject() -> ProjectMeshProject {
        .init(projectId: "project", name: "GrantTap", repositoryRoot: "/repo",
              canonicalRepositoryId: "github.com/example/granttap", baseRemote: nil,
              createdAt: now)
    }

    /// A computer reporting that it now holds the given policy.
    static func appliedStatus(_ policy: ProjectPolicy) -> ProjectPolicyStatus {
        ProjectPolicyStatus(
            type: "project.policy.status", sessionId: policy.projectId,
            projectId: policy.projectId, policy: policy,
            coverage: .init(
                projectId: policy.projectId, policyRevision: policy.revision,
                enforcement: policy.enforcement, requiredCapabilities: [.mcp],
                endpoints: [ProjectPolicyAcknowledgement(
                    projectId: policy.projectId, policyRevision: policy.revision,
                    endpointId: "mac", provider: "claude",
                    capabilities: [.init(kind: .mcp, status: .enforced)], observedAt: now + 1
                )], strictReady: true
            ),
            generatedAt: now + 1_000
        )
    }

    static func policyStatus(
        endpoint: String, provider: String, status: ProjectPolicyCoverageStatus,
        projectId: String = "project"
    ) -> ProjectPolicyStatus {
        let rules = [
            ProjectPolicyRule(
                ruleId: "granttap-default-mcp", projectId: projectId,
                selector: .init(kind: .mcp), effect: .ask,
                conditions: .init(endpointIds: [], providers: []), revision: 3,
                createdBy: "phone"
            ),
            ProjectPolicyRule(
                ruleId: "custom-release", projectId: projectId,
                selector: .init(kind: .deploy, displayName: "Production"), effect: .deny,
                conditions: .init(endpointIds: [], providers: []), revision: 3,
                createdBy: "security"
            ),
        ]
        let policy = ProjectPolicy(
            projectId: projectId, revision: 3, enforcement: .strict, rules: rules
        )
        let acknowledgement = ProjectPolicyAcknowledgement(
            projectId: projectId, policyRevision: 3, endpointId: endpoint,
            provider: provider, capabilities: [.init(kind: .mcp, status: status)],
            observedAt: now
        )
        return ProjectPolicyStatus(
            type: "project.policy.status", sessionId: projectId, projectId: projectId,
            policy: policy,
            coverage: .init(
                projectId: projectId, policyRevision: 3, enforcement: .strict,
                requiredCapabilities: [.mcp], endpoints: [acknowledgement],
                strictReady: status == .enforced
            ),
            generatedAt: now
        )
    }

    static func pairing(room: String) -> Pairing {
        .init(
            relayUrl: "ws://127.0.0.1:1", room: room, role: "phone",
            deviceName: "iPhone", senderId: "phone", myPublicKey: "public",
            mySecretKey: "secret", peerPublicKey: "peer"
        )
    }
}
