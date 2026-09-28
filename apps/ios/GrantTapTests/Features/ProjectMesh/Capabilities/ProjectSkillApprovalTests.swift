import XCTest
@testable import GrantTap

@MainActor
final class ProjectSkillApprovalTests: XCTestCase {
    func testCapabilitySourceDoesNotRouteEveryBindingToSnapshotPublisher() {
        let model = AppModel()
        var snapshot = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "Project",
                           canonicalRepositoryId: "repo", createdAt: 1),
            tasks: [], executions: [], claims: [], dependencies: [], events: [],
            generatedAt: 2
        )
        snapshot.publisherEndpointId = "mac-a"
        snapshot.bindings = [
            .init(bindingId: "a", projectId: "project", endpointId: "mac-a",
                  repositoryId: "repo", displayName: "A", available: true),
            .init(bindingId: "b", projectId: "project", endpointId: "mac-b",
                  repositoryId: "repo", displayName: "B", available: true),
        ]
        XCTAssertTrue(model.registerCapabilitySource(snapshot: snapshot, room: "room-a"))
        XCTAssertEqual(model.meshComputerRoomByEndpointId["mac-a"], "room-a")
        XCTAssertNil(model.meshComputerRoomByEndpointId["mac-b"])
    }

    func testExactBundleApprovalPreservesOtherPolicyAndAsksOnDrift() throws {
        let current = ProjectPolicy(
            projectId: "project", revision: 4, enforcement: .bestAvailable,
            rules: [ProjectPolicyRule(
                ruleId: "unrelated", projectId: "project",
                selector: ProjectPolicySelector(kind: .deploy), effect: .deny,
                conditions: ProjectPolicyConditions(endpointIds: [], providers: []),
                revision: 4, createdBy: "owner"
            )]
        )
        let digest = String(repeating: "a", count: 64)
        let skill = ProjectSharedSkill(
            name: "review", endpointId: "mac-a", digest: digest, state: "discovered"
        )
        let updated = try XCTUnwrap(ProjectSkillApproval.policy(
            current: current, draft: nil, projectId: "project", skill: skill,
            enforcement: .bestAvailable
        ))
        XCTAssertEqual(updated.revision, 5)
        XCTAssertEqual(updated.rules.first { $0.ruleId == "unrelated" }?.effect, .deny)
        let approvals = updated.rules.filter { $0.ruleId.hasPrefix("granttap-approved-skill-") }
        XCTAssertEqual(approvals.count, 6)
        XCTAssertEqual(Set(approvals.map { $0.conditions.endpointIds }), [["mac-a"]])
        XCTAssertEqual(approvals.filter { $0.effect == .allow }.count, 3)
        XCTAssertEqual(approvals.filter { $0.effect == .ask }.count, 3)
        XCTAssertTrue(approvals.allSatisfy {
            $0.selector.fingerprint?.expected?.scriptHash == digest
        })
        XCTAssertTrue(approvals.allSatisfy {
            $0.selector.fingerprint?.expected?.origin == "project-skill"
        })
        XCTAssertTrue(ProjectGovernanceWireValidator.validSet(ProjectPolicySet(
            type: "project.policy.set", sessionId: "project", projectId: "project",
            expectedRevision: 4, policy: updated, createdAt: 1
        )))
    }

    func testUnknownOrConflictingBundleCannotBeApproved() {
        let unknown = ProjectSharedSkill(name: "review", endpointId: "mac", state: "discovered")
        XCTAssertNil(ProjectSkillApproval.policy(
            current: nil, draft: nil, projectId: "project", skill: unknown,
            enforcement: .bestAvailable
        ))
        let conflict = ProjectSharedSkill(
            name: "review", endpointId: "mac", digest: String(repeating: "a", count: 64),
            state: "conflict"
        )
        XCTAssertNil(ProjectSkillApproval.policy(
            current: nil, draft: nil, projectId: "project", skill: conflict,
            enforcement: .bestAvailable
        ))
    }
}
