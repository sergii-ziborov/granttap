import SwiftUI
import TweetNacl
import XCTest
@testable import GrantTap

/// What a member's phone may speak for in a shared Project, and what it may
/// not: another member's execution, another member's claim, another member's
/// chat, or the terms a turn runs under in a chat it only writes to.
@MainActor
final class MemberContributionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ProjectMeshPersistence.clear()
    }

    override func tearDown() {
        MemberLinkStore.remove()
        ProjectMeshPersistence.clear()
        super.tearDown()
    }

    /// One member's copy of the mesh is not an authority over another's work.
    func testAMemberSpeaksOnlyForWhatTheirOwnSideBroughtIn() throws {
        let (model, olga) = try MemberHubFixture.hub()
        let otherRoom = String(repeating: "c", count: 32)
        let pavel = MemberLink(
            id: otherRoom, projectId: "project", name: "Pavel", role: .member, rules: .preset(.member),
            createdAt: 1_000, inviteExpiresAt: 2_000, joinedAt: 1_500,
            hubPairing: try MemberHubFixture.pairing(role: "machine", room: otherRoom)
        )
        model.memberLinks.append(pavel)
        model.meshEndpointRelaysById[pavel.id] = RelayClient(pairing: pavel.hubPairing)

        func carrying(
            tasks: [ProjectMeshTask], executions: [ExecutionSessionLink], claims: [ProjectResourceClaim], at: Double
        ) -> ProjectMeshSnapshot {
            let base = MemberHubFixture.snapshot()
            return ProjectMeshSnapshot(
                type: base.type, sessionId: base.sessionId, projectId: base.projectId, project: base.project,
                tasks: tasks, executions: executions, claims: claims, dependencies: [], events: [], generatedAt: at
            )
        }

        func brought(_ owner: String, claim: String, resource: String, at: Double = 3) -> ProjectMeshSnapshot {
            carrying(
                tasks: [.init(taskId: "t-\(owner)", projectId: "project", title: "Work", goal: "g",
                              state: "working", ownerSessionId: owner, createdAt: 1, updatedAt: 2)],
                executions: [.init(taskId: "t-\(owner)", sessionId: owner, provider: "claude",
                                   computerId: "\(owner)-computer", workspace: "/repo", startedAt: 1)],
                claims: [.init(claimId: claim, projectId: "project", taskId: "t-\(owner)", ownerSessionId: owner,
                               resource: resource, mode: "claim", createdAt: 1, expiresAt: 9_000_000_000_000)],
                at: at
            )
        }

        XCTAssertTrue(model.acceptMemberSnapshot(try JSONEncoder().encode(brought("olga-chat", claim: "c-olga", resource: "src/a/**")), link: olga))
        XCTAssertEqual(model.meshSnapshots["project"]?.claims.map(\.claimId), ["c-olga"])
        XCTAssertEqual(model.meshContributionRooms[MemberContribution.claimKey("c-olga")], olga.id)

        // Pavel republishes what he was handed, with the claim in his own name.
        let spoofed = carrying(
            tasks: [.init(taskId: "t-olga-chat", projectId: "project", title: "Work", goal: "g",
                          state: "working", ownerSessionId: "olga-chat", createdAt: 1, updatedAt: 6)],
            executions: [.init(taskId: "t-olga-chat", sessionId: "olga-chat", provider: "claude",
                               computerId: "pavel-computer", workspace: "/elsewhere", startedAt: 5)],
            claims: [.init(claimId: "c-olga", projectId: "project", taskId: "t-olga-chat", ownerSessionId: "pavel-chat",
                           resource: "src/a/**", mode: "claim", createdAt: 4, expiresAt: 9_000_000_000_000)],
            at: 5
        )
        XCTAssertTrue(model.acceptMemberSnapshot(try JSONEncoder().encode(spoofed), link: pavel))
        let claims = try XCTUnwrap(model.meshSnapshots["project"]?.claims)
        XCTAssertEqual(claims.map(\.ownerSessionId), ["olga-chat"], "a claim's owner is not another member's to change")
        XCTAssertEqual(model.meshSnapshots["project"]?.executions.map(\.computerId), ["olga-chat-computer"],
                       "nor is another member's execution his to move")

        // What Pavel's own side brings in is his to speak for.
        XCTAssertTrue(model.acceptMemberSnapshot(try JSONEncoder().encode(brought("pavel-chat", claim: "c-pavel", resource: "src/b/**", at: 7)), link: pavel))
        XCTAssertEqual(model.meshSnapshots["project"]?.claims.map(\.claimId).sorted(), ["c-olga", "c-pavel"])

        // Nor may he post an event in the name of a chat that is not his.
        let event = ProjectMeshEvent(
            type: "mesh.event", sessionId: "t-olga-chat", eventId: "e-1", projectId: "project", taskId: "t-olga-chat",
            sourceSessionId: "olga-chat", eventType: "TASK_PROGRESS", createdAt: 6, expiresAt: 9_000_000_000_000,
            payload: .init(summary: "done")
        )
        XCTAssertFalse(model.acceptMemberEvent(try JSONEncoder().encode(event), link: pavel))
        XCTAssertTrue(model.acceptMemberEvent(try JSONEncoder().encode(event), link: olga))

        // The map of who spoke for what stays bounded.
        model.meshContributionRooms = Dictionary(
            uniqueKeysWithValues: (0...AppModel.maxMemberContributionRows).map { ("stale-\($0)", pavel.id) }
        )
        model.rememberMemberContribution(MemberHubFixture.snapshot(), room: pavel.id)
        XCTAssertLessThanOrEqual(model.meshContributionRooms.count, AppModel.maxMemberContributionRows)

        // Removed, a member speaks for nothing; invited again, they may speak
        // for their own work anew through the new pairing.
        model.meshContributionRooms[MemberContribution.claimKey("c-pavel")] = pavel.id
        model.removeMemberLink(id: pavel.id)
        XCTAssertFalse(model.meshContributionRooms.values.contains(pavel.id))
    }

    /// A member writes what is said in a chat, never how the chat runs.
    func testAMembersMessageCarriesItsTextAndNotTheTermsOfTheTurn() throws {
        let (model, link) = try MemberHubFixture.hub()
        let message = UserMessage(
            type: "user.message", messageId: "m-1", text: "Please run the tests", agent: "codex", cwd: "/elsewhere",
            requestId: "r-1", sessionId: "s1", preferredMcp: "other", skill: "deploy", model: "opus",
            permissionMode: "bypassPermissions", effort: "high", createdAt: 7
        )
        XCTAssertTrue(model.forwardMemberMessage(try JSONEncoder().encode(message), link: link))
        let forwarded = AppModel.memberMessage(message, sessionId: "s1", messageId: "m-1")
        XCTAssertEqual(forwarded.text, "Please run the tests")
        XCTAssertEqual(forwarded.sessionId, "s1")
        XCTAssertEqual(forwarded.requestId, "r-1")
        XCTAssertNil(forwarded.permissionMode, "a member does not set the provider's permission mode from another phone")
        XCTAssertNil(forwarded.model)
        XCTAssertNil(forwarded.effort)
        XCTAssertNil(forwarded.agent)
        XCTAssertNil(forwarded.cwd)
        XCTAssertNil(forwarded.skill)
        XCTAssertNil(forwarded.preferredMcp)
        XCTAssertEqual(model.memberForwardedMessages["m-1"], link.id)
    }
}
