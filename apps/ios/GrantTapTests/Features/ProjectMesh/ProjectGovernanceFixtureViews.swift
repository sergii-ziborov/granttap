import SwiftUI
import XCTest
@testable import GrantTap

/// The Project a Governance screen is rendered against, and the way a test
/// renders one.
@MainActor
enum ProjectGovernanceViewFixtures {
    static let now = 1_800_000_000_000.0

    static func policyProjection() -> ProjectGovernanceProjection {
        ProjectGovernanceProjection(
            projectId: "project", revision: 7, enforcement: .bestAvailable,
            rules: [
                .init(ruleId: "allow-github", effect: .allow, capabilityKind: "mcp",
                      displayName: "GitHub", provider: "claude"),
                .init(ruleId: "ask-deploy", effect: .ask, capabilityKind: "deploy"),
                .init(ruleId: "deny-unknown", effect: .deny, capabilityKind: "mcp",
                      fingerprintConfidence: "unknown"),
            ],
            coverage: [
                coverage("claude", "Shell", .enforced),
                coverage("grok", "Shell", .observed),
                coverage("cursor", "Skills", .unsupported),
                coverage("codex", "MCP", .unknown),
            ], updatedAt: now
        )
    }

    static func coverage(
        _ provider: String, _ capability: String, _ status: ProjectPolicyCoverageStatus
    ) -> ProjectPolicyCoverageSummary {
        .init(endpointId: provider == "grok" ? "workstation" : "mac",
              provider: provider, capability: capability, status: status)
    }

    static func projectSnapshot() -> ProjectMeshSnapshot {
        ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "GrantTap",
                           repositoryRoot: "/Users/private/granttap",
                           canonicalRepositoryId: "github.com/example/granttap",
                           baseRemote: nil, createdAt: now),
            bindings: [
                binding("one", "mac", "ios", "/Users/private/granttap"),
                binding("two", "mac", "runtime", "/Users/private/runtime"),
                binding("three", "workstation", "relay", "D:\\private\\relay"),
            ], tasks: [], executions: [], claims: [], dependencies: [], events: [],
            generatedAt: now
        )
    }

    static func binding(
        _ id: String, _ endpoint: String, _ repository: String, _ path: String
    ) -> ProjectBindingSummary {
        .init(bindingId: id, projectId: "project", endpointId: endpoint,
              repositoryId: repository, displayName: repository.capitalized,
              localPathHint: path, available: true, revision: "abcdef0123456789")
    }

    static func render<Content: View>(_ content: Content) {
        let host = UIHostingController(rootView: content)
        host.loadViewIfNeeded()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        host.beginAppearanceTransition(true, animated: false)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        host.endAppearanceTransition()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertGreaterThan(host.sizeThatFits(in: host.view.bounds.size).height, 0)
    }
}
