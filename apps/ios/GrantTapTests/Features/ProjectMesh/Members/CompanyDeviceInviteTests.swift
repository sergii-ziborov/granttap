import XCTest
@testable import GrantTap

@MainActor
final class CompanyDeviceInviteTests: XCTestCase {
    func testHistoricalKnowledgeRepositoryRequiresItsOwnGrant() {
        var snapshot = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: ProjectMeshProject(projectId: "project", name: "Project", canonicalRepositoryId: "repo-a", createdAt: 1),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1
        )
        let account = CompanyAccount(id: "member", name: "Member", repositoryAccess: .selected(["repo-a"]))
        XCTAssertTrue(CompanyAccountPolicy.canReceive(snapshot, account: account))
        snapshot.knowledge = [ProjectKnowledgeRecord(
            projectId: "project", taskId: "task", recordId: "old-result", category: "outcome", content: "Observed result",
            source: "execution", sourceRef: "execution-1", visibility: "project", repositoryId: "repo-b",
            commitSha: "revision", recordedAt: 1, streamVersion: 1
        )]
        XCTAssertFalse(CompanyAccountPolicy.canReceive(snapshot, account: account))
    }

    func testCompanyDeviceCanPairBeforeAnyComputerOrProject() async throws {
        let model = AppModel()
        model.connectionRegistry = .empty
        model.meshSnapshots = [:]
        model.memberLinks = []
        model.agentMeshPreferences.meshEnabled = false
        model.companyAccounts = [CompanyAccount(
            id: "company-person", name: "Olga", repositoryAccess: .selected([])
        )]
        defer {
            model.meshEndpointRelaysById.values.forEach { $0.disconnect() }
            for link in model.memberLinks { _ = model.removeMemberLink(id: link.id) }
        }

        let uri = try await model.createMemberInvite(
            projectId: "", name: "Olga's iPad", role: .member,
            rules: .preset(.member), projectIds: [], accountId: "company-person",
            parker: { _, _ in 201 }
        )
        let link = try XCTUnwrap(model.memberLinks.first)
        XCTAssertTrue(uri.hasPrefix("granttap://pair-v2?"))
        XCTAssertEqual(link.companyAccountId, "company-person")
        XCTAssertTrue(link.projectIds.isEmpty, "pairing grants no Mesh Project")
        XCTAssertFalse(link.allowsProject(""))
        XCTAssertTrue(link.hubPairing.relayUrl.contains("relay.granttap.com"))
        XCTAssertNotNil(model.meshEndpointRelaysById[link.id], "account pairing is available with Project Mesh off")

        model.companyAccounts[0].disabled = true
        do {
            _ = try await model.createMemberInvite(
                projectId: "", name: "Another iPad", role: .member,
                rules: .preset(.member), projectIds: [], accountId: "company-person",
                parker: { _, _ in 201 }
            )
            XCTFail("a paused account must not issue a device code")
        } catch MemberInviteError.invalidAccount { }
    }
}
