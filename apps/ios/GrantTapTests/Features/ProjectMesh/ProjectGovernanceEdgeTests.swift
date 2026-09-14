import XCTest
@testable import GrantTap

final class ProjectGovernanceEdgeTests: XCTestCase {
    func testALaterReadingOfTheSameRevisionReplacesAStaleCopy() throws {
        // A computer that reads its policy again and publishes a corrected copy
        // under the same revision used to be refused for good. The screen then
        // said "0 rules" while rules were being enforced, and Save stayed grey
        // because the draft matched the copy nothing could replace.
        let base = ProjectGovernanceFixtures.status()
        let empty = restated(base, policy: ProjectPolicy(
            projectId: "project", revision: 3, enforcement: .strict, rules: []
        ), at: base.generatedAt)
        let stale = try XCTUnwrap(ProjectGovernanceLogic.merged(current: nil, status: empty))
        XCTAssertEqual(stale.rules.count, 0)

        let later = restated(base, policy: base.policy, at: base.generatedAt + 1_000)
        let fresh = try XCTUnwrap(
            ProjectGovernanceLogic.merged(current: stale, status: later)
        )
        XCTAssertEqual(fresh.rules.count, 1, "the computer's later reading is the truth")
        XCTAssertEqual(fresh.policy?.rules.first?.effect, .ask)

        // A reading no newer than the one already held is still a diverging
        // peer, and it must not overwrite the Project's policy.
        let sameMoment = restated(base, policy: ProjectPolicy(
            projectId: "project", revision: 3, enforcement: .strict, rules: []
        ), at: later.generatedAt)
        XCTAssertEqual(
            ProjectGovernanceLogic.merged(current: fresh, status: sameMoment)?.rules.count, 1
        )
    }

    func testLogicNeverMergesAnotherProjectAndDeliveryFailureNeedsEveryTarget() {
        let firstStatus = ProjectGovernanceFixtures.status(projectId: "first")
        let current = ProjectGovernanceLogic.merged(current: nil, status: firstStatus)
        let otherStatus = ProjectGovernanceFixtures.status(projectId: "other")
        XCTAssertEqual(
            ProjectGovernanceLogic.merged(current: current, status: otherStatus), current
        )
        let otherAck = ProjectGovernanceFixtures.acknowledgement(projectId: "other")
        XCTAssertEqual(ProjectGovernanceLogic.merged(current: current, ack: otherAck), current)

        let failed = ProjectPolicyDeliveryTracker(count: 2)
        XCTAssertFalse(failed.resolve(error: NSError(domain: "test", code: 1)))
        XCTAssertTrue(failed.resolve(error: NSError(domain: "test", code: 2)))
        XCTAssertFalse(failed.resolve(error: NSError(domain: "test", code: 3)))
        let delivered = ProjectPolicyDeliveryTracker(count: 2)
        XCTAssertFalse(delivered.resolve(error: nil))
        XCTAssertFalse(delivered.resolve(error: NSError(domain: "test", code: 4)))
    }

    func testEmptyGovernanceSaveReplacesStaleCache() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = root.appendingPathComponent("governance.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let status = ProjectGovernanceFixtures.status()
        let projection = try XCTUnwrap(ProjectGovernanceLogic.merged(current: nil, status: status))
        ProjectGovernancePersistence.save([projection.projectId: projection], to: url)
        XCTAssertEqual(ProjectGovernancePersistence.load(from: url).count, 1)
        ProjectGovernancePersistence.save([:], to: url)
        XCTAssertTrue(ProjectGovernancePersistence.load(from: url).isEmpty)
    }

    func testFingerprintHashUsesProtocolAsciiHex() {
        let unicodeHash = String(repeating: "Ｆ", count: 64)
        let fingerprint = ProjectCapabilityFingerprint(
            kind: .mcp, displayName: "GitHub", executablePathHash: unicodeHash,
            confidence: .exact
        )
        let rule = ProjectPolicyRule(
            ruleId: "exact", projectId: "project",
            selector: ProjectPolicySelector(
                kind: .mcp,
                fingerprint: ProjectFingerprintPredicate(match: .exact, expected: fingerprint)
            ), effect: .allow,
            conditions: ProjectPolicyConditions(endpointIds: [], providers: []),
            revision: 1, createdBy: "phone"
        )
        let request = ProjectPolicySet(
            type: "project.policy.set", sessionId: "project", projectId: "project",
            expectedRevision: 0,
            policy: ProjectPolicy(
                projectId: "project", revision: 1, enforcement: .bestAvailable, rules: [rule]
            ), createdAt: 1
        )
        XCTAssertFalse(ProjectGovernanceWireValidator.validSet(request))
    }

    /// A Project the computer has never had a policy for arrives at revision 0.
    /// Rejecting it left Governance empty with no way to author the first
    /// revision, because the editor only unlocks once a policy is reported.
    func testUnauthoredProjectPolicyIsAcceptedSoTheFirstRevisionCanBeAuthored() throws {
        let unauthored = ProjectPolicyStatus(
            type: "project.policy.status", sessionId: "project", projectId: "project",
            policy: ProjectPolicy(
                projectId: "project", revision: 0, enforcement: .bestAvailable, rules: []
            ),
            coverage: ProjectPolicyCoverage(
                projectId: "project", policyRevision: 0, enforcement: .bestAvailable,
                requiredCapabilities: [], endpoints: [], strictReady: false
            ), generatedAt: 1_800_000_000_000
        )
        XCTAssertTrue(ProjectGovernanceWireValidator.validStatus(unauthored))

        let projection = ProjectGovernanceLogic.merged(current: nil, status: unauthored)
        XCTAssertEqual(projection?.revision, 0)
        XCTAssertNotNil(projection?.policy, "the editor unlocks on a reported policy")

        // Authoring from an unauthored Project produces revision 1, which the
        // set validator accepts against an expected revision of 0.
        let policy = ProjectGovernanceLogic.updatedPolicy(
            current: try XCTUnwrap(projection?.policy), projectId: "project",
            enforcement: .strict, defaults: [.mcp: .ask], createdBy: "granttap-phone"
        )
        XCTAssertEqual(policy.revision, 1)
        XCTAssertTrue(ProjectGovernanceWireValidator.validSet(ProjectPolicySet(
            type: "project.policy.set", sessionId: "project", projectId: "project",
            expectedRevision: 0, policy: policy, createdAt: 1_800_000_000_000
        )))
    }

    /// The same status read again: a different policy, at a different moment.
    private func restated(
        _ status: ProjectPolicyStatus, policy: ProjectPolicy, at generatedAt: Double
    ) -> ProjectPolicyStatus {
        ProjectPolicyStatus(
            type: status.type, sessionId: status.sessionId, projectId: status.projectId,
            policy: policy, coverage: status.coverage, generatedAt: generatedAt
        )
    }
}
