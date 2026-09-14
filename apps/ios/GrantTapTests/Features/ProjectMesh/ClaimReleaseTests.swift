import SwiftUI
import TweetNacl
import XCTest
@testable import GrantTap

/// The person's own release of a claim: a command of its own, sent to the
/// Project's computers, let through for a member by role, and gone from the
/// phone's picture at once.
@MainActor
final class ClaimReleaseTests: XCTestCase {
    private let own = String(repeating: "a", count: 32)
    private let linkRoom = String(repeating: "b", count: 32)

    override func setUp() {
        super.setUp()
        ProjectMeshPersistence.clear()
    }

    override func tearDown() {
        MemberLinkStore.remove()
        ProjectMeshPersistence.clear()
        super.tearDown()
    }

    private func pairing(role: String, room: String) throws -> Pairing {
        let me = try NaclBox.keyPair()
        let peer = try NaclBox.keyPair()
        return Pairing(relayUrl: "wss://relay.granttap.app", room: room, role: role, deviceName: "Mac", senderId: "s",
                       myPublicKey: me.publicKey.base64EncodedString(), mySecretKey: me.secretKey.base64EncodedString(),
                       peerPublicKey: peer.publicKey.base64EncodedString())
    }

    private func claim(_ id: String, owner: String = "dead-agent") -> ProjectResourceClaim {
        ProjectResourceClaim(claimId: id, projectId: "project", taskId: "task", ownerSessionId: owner,
                             resource: "src/auth/**", mode: "claim", createdAt: 1, expiresAt: 9e12)
    }

    private func model() throws -> (AppModel, MemberLink) {
        let model = AppModel()
        model.memberLinks = []
        model.agentMeshPreferences.meshEnabled = true
        let mac = try pairing(role: "phone", room: own)
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: mac, mode: .add, prefer: true)
        model.relaysByRoom[own] = RelayClient(pairing: mac)
        model.meshProjectSourceRooms["project"] = [own]
        model.meshSnapshots["project"] = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: ProjectMeshProject(projectId: "project", name: "GrantTap", repositoryRoot: "/repo", canonicalRepositoryId: "repo", createdAt: 1),
            tasks: [ProjectMeshTask(taskId: "task", projectId: "project", title: "Pairing", goal: "G", state: "working",
                                    ownerSessionId: "dead-agent", createdAt: 1, updatedAt: 1)],
            executions: [], claims: [claim("c-1"), claim("c-2", owner: "other")], dependencies: [], events: [], generatedAt: 2
        )
        let link = MemberLink(id: linkRoom, projectId: "project", name: "Olga", role: .admin, rules: .preset(.admin), createdAt: 1,
                              inviteExpiresAt: 2, joinedAt: 1, hubPairing: try pairing(role: "machine", room: linkRoom))
        model.memberLinks = [link]
        model.meshEndpointRelaysById[linkRoom] = RelayClient(pairing: link.hubPairing)
        model.meshEndpointRoomToId[linkRoom] = linkRoom
        model.meshProjectSourceRooms["project"]?.insert(linkRoom)
        return (model, link)
    }

    func testThePersonReleasesAClaimAndItLeavesThePhonesPictureAtOnce() throws {
        let (model, _) = try model()
        XCTAssertEqual(model.releaseClaimByPerson(projectId: "project", claimId: "c-1", reason: "gone"), [own],
                       "to each of the Project's computers, not to a member's phone")
        XCTAssertEqual(model.meshSnapshots["project"]?.claims.map(\.claimId), ["c-2"])
        XCTAssertEqual(model.releaseClaimByPerson(projectId: "project", claimId: ""), [])
        model.agentMeshPreferences.meshEnabled = false
        XCTAssertEqual(model.releaseClaimByPerson(projectId: "project", claimId: "c-2"), [], "with the Mesh off, nothing is sent")
        XCTAssertEqual(model.meshSnapshots["project"]?.claims.count, 1)
        // The wire shape the computer checks.
        let request = MeshClaimRelease(type: "mesh.claim.release", sessionId: "project", projectId: "project", claimId: "c-1", createdAt: 1)
        XCTAssertTrue(request.isWellFormed)
        XCTAssertFalse(MeshClaimRelease(type: "mesh.claim.release", sessionId: "other", projectId: "project", claimId: "c-1", createdAt: 1).isWellFormed)
        XCTAssertFalse(MeshClaimRelease(type: "mesh.claim.release", sessionId: "project", projectId: "project", claimId: "", createdAt: 1).isWellFormed)
        XCTAssertFalse(MeshClaimRelease(type: "mesh.claim.release", sessionId: "project", projectId: "project", claimId: "c", reason: "", createdAt: 1).isWellFormed)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: RelayClient.encodeOmittingNulls(request)) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "mesh.claim.release")
        XCTAssertNil(object["reason"], "absent, not null, on the wire")
    }

    func testAMembersReleaseIsLetThroughByRoleToThePersonsOwnComputers() throws {
        let (model, admin) = try model()
        let request = MeshClaimRelease(type: "mesh.claim.release", sessionId: "project", projectId: "project", claimId: "c-1",
                                       reason: "stuck", createdAt: 1)
        model.handleMemberPayload(type: "mesh.claim.release", data: try JSONEncoder().encode(request), linkId: admin.id)
        XCTAssertEqual(model.meshSnapshots["project"]?.claims.map(\.claimId), ["c-2"], "an admin's release went through and is reflected here")
        XCTAssertTrue(MemberHubPolicy.allows("mesh.claim.release", rules: .preset(.admin)))
        XCTAssertFalse(MemberHubPolicy.allows("mesh.claim.release", rules: .preset(.member)), "a member may post, not override")
        XCTAssertFalse(MemberHubPolicy.refusal("mesh.claim.release").isEmpty)
        // Another Project's claim through this link is not this link's to release; a malformed one neither.
        let foreign = MeshClaimRelease(type: "mesh.claim.release", sessionId: "other", projectId: "other", claimId: "c-2", createdAt: 1)
        XCTAssertEqual(model.forwardMemberClaimRelease(try JSONEncoder().encode(foreign), link: admin), [])
        XCTAssertEqual(model.forwardMemberClaimRelease(Data("{}".utf8), link: admin), [])
        XCTAssertEqual(model.meshSnapshots["project"]?.claims.count, 1)
        // A plain member is refused by the rules before anything is forwarded.
        model.updateMemberLink(MemberLinkEdits.withRole(admin, .member))
        let second = MeshClaimRelease(type: "mesh.claim.release", sessionId: "project", projectId: "project", claimId: "c-2", createdAt: 1)
        model.handleMemberPayload(type: "mesh.claim.release", data: try JSONEncoder().encode(second), linkId: admin.id)
        XCTAssertEqual(model.meshSnapshots["project"]?.claims.map(\.claimId), ["c-2"], "still held")
    }

    func testARefusalPutsTheClaimBackWithItsReasonAndAnAnswerFindsTheMemberWhoAsked() throws {
        let (model, admin) = try model()
        // From here: released, kept aside, then refused by a computer — back it comes, with the reason.
        model.releaseClaimByPerson(projectId: "project", claimId: "c-1")
        XCTAssertEqual(model.meshSnapshots["project"]?.claims.map(\.claimId), ["c-2"])
        let unknownOnOne = MeshClaimReleaseResult(type: "mesh.claim.release.result", sessionId: "project", projectId: "project",
                                                  claimId: "c-1", ok: false, reason: "unknown_claim", generatedAt: 2)
        model.receive(unknownOnOne, fromRoom: own)
        XCTAssertEqual(model.meshSnapshots["project"]?.claims.count, 1, "one computer never had it; another may still say yes")
        let refused = MeshClaimReleaseResult(type: "mesh.claim.release.result", sessionId: "project", projectId: "project",
                                             claimId: "c-1", ok: false, reason: "other_project", detail: "That claim belongs to another Project.", generatedAt: 3)
        model.receive(refused, fromRoom: own)
        XCTAssertEqual(model.meshSnapshots["project"]?.claims.map(\.claimId).sorted(), ["c-1", "c-2"], "refused, so back")
        XCTAssertEqual(model.claimReleaseNotices["c-1"], "That claim belongs to another Project.")
        model.releaseClaimByPerson(projectId: "project", claimId: "c-1")
        XCTAssertNil(model.claimReleaseNotices["c-1"], "trying again clears the old reason")
        let done = MeshClaimReleaseResult(type: "mesh.claim.release.result", sessionId: "project", projectId: "project",
                                          claimId: "c-1", ok: true, generatedAt: 4)
        model.receive(done, fromRoom: own)
        XCTAssertEqual(model.meshSnapshots["project"]?.claims.map(\.claimId), ["c-2"], "done, and it stays gone")
        XCTAssertTrue(model.releasedClaims.isEmpty)
        // The wire shape: a refusal says why, and words for the person exist for every reason.
        XCTAssertFalse(MeshClaimReleaseResult(type: "mesh.claim.release.result", sessionId: "project", projectId: "project",
                                              claimId: "c", ok: false, generatedAt: 1).isWellFormed)
        for reason in MeshClaimReleaseResult.reasons {
            let result = MeshClaimReleaseResult(type: "mesh.claim.release.result", sessionId: "project", projectId: "project",
                                                claimId: "c", ok: false, reason: reason, generatedAt: 1)
            XCTAssertTrue(result.isWellFormed, reason)
            XCTAssertFalse(result.message.isEmpty, reason)
        }
        XCTAssertFalse(done.message.isEmpty)

        // A member asked through this phone: the computers' answer goes back to that member.
        let request = MeshClaimRelease(type: "mesh.claim.release", sessionId: "project", projectId: "project", claimId: "c-2",
                                       requestId: "r-7", createdAt: 5)
        XCTAssertEqual(model.forwardMemberClaimRelease(try JSONEncoder().encode(request), link: admin), [own])
        XCTAssertEqual(model.memberForwardedReleases[AppModel.releaseKey("c-2", requestId: "r-7")], admin.id)
        let answer = MeshClaimReleaseResult(type: "mesh.claim.release.result", sessionId: "project", projectId: "project",
                                            claimId: "c-2", ok: false, reason: "unknown_claim", requestId: "r-7", generatedAt: 6)
        model.receive(answer, fromRoom: own)
        XCTAssertTrue(model.memberForwardedReleases.isEmpty, "handed to the member, not kept here")
        XCTAssertNil(model.claimReleaseNotices["c-2"], "not this phone's refusal to show")
        // A member without the right is refused with a reason of its own; with no computer, likewise.
        let refusal = model.refuseMemberRelease(request, link: admin, reason: "not_allowed", detail: MemberHubPolicy.refusal("mesh.claim.release"))
        XCTAssertEqual(refusal.reason, "not_allowed")
        XCTAssertTrue(refusal.isWellFormed)
        model.meshProjectSourceRooms["project"] = [linkRoom]
        XCTAssertEqual(model.forwardMemberClaimRelease(try JSONEncoder().encode(request), link: admin), [])
        model.meshProjectSourceRooms["project"] = [own, linkRoom]
        // A member's refusal arrives on the member's phone like a computer's answer.
        model.releaseClaimByPerson(projectId: "project", claimId: "c-2")
        model.receive(refusal, fromRoom: own)
        XCTAssertEqual(model.claimReleaseNotices["c-2"], MemberHubPolicy.refusal("mesh.claim.release"))
    }

    /// A computer that was away publishes what it last knew; a release is not
    /// undone by that.
    func testAReleasedClaimDoesNotComeBackWithALateSnapshot() throws {
        let (model, _) = try model()
        let projectSnapshot = try XCTUnwrap(model.meshSnapshots["project"])
        XCTAssertEqual(model.releaseClaimByPerson(projectId: "project", claimId: "c-1"), [own])
        XCTAssertEqual(model.meshSnapshots["project"]?.claims.map(\.claimId), ["c-2"])

        // The same snapshot as before the release, arriving late.
        let late = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project", project: projectSnapshot.project,
            tasks: projectSnapshot.tasks, executions: [], claims: [claim("c-1"), claim("c-2", owner: "other")],
            dependencies: [], events: [], generatedAt: 9
        )
        model.receive(late, fromRoom: own)
        XCTAssertEqual(model.meshSnapshots["project"]?.claims.map(\.claimId), ["c-2"], "released is released")

        // A refusal puts the claim back, and with it the right to hear of it again.
        model.receive(MeshClaimReleaseResult(
            type: "mesh.claim.release.result", sessionId: "project", projectId: "project", claimId: "c-1",
            ok: false, reason: "not_allowed", requestId: nil, generatedAt: 10
        ), fromRoom: own)
        XCTAssertEqual(model.meshSnapshots["project"]?.claims.map(\.claimId).sorted(), ["c-1", "c-2"])
        model.receive(late, fromRoom: own)
        XCTAssertEqual(model.meshSnapshots["project"]?.claims.count, 2)

        // Past the claim's own expiry the release is forgotten: a claim of the
        // same id made afterwards is a new one.
        XCTAssertEqual(model.releaseClaimByPerson(projectId: "project", claimId: "c-1"), [own])
        XCTAssertTrue(model.isReleasedClaim("c-1", at: 1_000))
        XCTAssertFalse(model.isReleasedClaim("c-1", at: 9e12 + 1))
        XCTAssertFalse(model.isReleasedClaim("never-released", at: 1_000))
        model.receive(late, fromRoom: own)
        XCTAssertEqual(model.meshSnapshots["project"]?.claims.map(\.claimId).sorted(), ["c-1", "c-2"],
                       "and what arrives after that is taken as it comes")
    }

    func testTheRouteScreenOffersTheReleaseOnEveryClaim() throws {
        let (model, _) = try model()
        model.meshSnapshots["project"]?.claims.append(
            ProjectResourceClaim(claimId: "c-3", projectId: "project", taskId: "task-other", ownerSessionId: "peer",
                                 resource: "src/auth/login.ts", mode: "claim", createdAt: 1, expiresAt: 9e12)
        )
        model.meshSnapshots["project"]?.tasks.append(
            ProjectMeshTask(taskId: "task-other", projectId: "project", title: "Other", goal: "G", state: "working",
                            ownerSessionId: "peer", createdAt: 1, updatedAt: 1)
        )
        let route = TaskRoute(projectId: "project", taskId: "task")
        model.claimReleaseNotices["c-1"] = "Only an admin of this Project may release a claim."
        RenderProbe.render(TaskRouteView(route: route, model: model, onOpenSession: { _ in }))
        RenderProbe.render(TaskRouteView(route: route, model: model, onOpenSession: { _ in }, presentedAsSheet: false))
        model.forgetClaim("c-3", projectId: "project")
        XCTAssertEqual(model.meshSnapshots["project"]?.claims.count, 2)
        model.forgetClaim("never", projectId: "project")
        model.forgetClaim("c-1", projectId: "nowhere")
    }
}
