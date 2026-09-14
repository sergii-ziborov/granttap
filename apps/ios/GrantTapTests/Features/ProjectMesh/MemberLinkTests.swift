import SwiftUI
import TweetNacl
import XCTest
@testable import GrantTap

@MainActor
final class MemberLinkTests: XCTestCase {
    private let service = "com.ziborov.granttap.member-links.tests"

    override func tearDown() {
        MemberLinkStore.remove(service: service)
        MemberLinkStore.remove()
        super.tearDown()
    }

    private func pairing(role: String = "phone", room: String = String(repeating: "a", count: 32)) throws -> Pairing {
        let me = try NaclBox.keyPair()
        let peer = try NaclBox.keyPair()
        return Pairing(
            relayUrl: "wss://relay.granttap.app", room: room, role: role, deviceName: "Mac", senderId: "s",
            myPublicKey: me.publicKey.base64EncodedString(), mySecretKey: me.secretKey.base64EncodedString(),
            peerPublicKey: peer.publicKey.base64EncodedString()
        )
    }

    private func snapshot(_ projectId: String = "project") -> ProjectMeshSnapshot {
        let project = ProjectMeshProject(
            projectId: projectId, name: "GrantTap", repositoryRoot: "/repo",
            canonicalRepositoryId: "repo", createdAt: 1
        )
        return ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: projectId, projectId: projectId,
            project: project, tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1
        )
    }

    private func link(rules: MemberRules, joined: Bool = false) throws -> MemberLink {
        MemberLink(
            id: String(repeating: "b", count: 32), projectId: "project", name: "Olga", role: .member, rules: rules,
            createdAt: 1_000, inviteExpiresAt: 1_000 + 15 * 60_000, joinedAt: joined ? 2_000 : nil,
            hubPairing: try pairing(role: "machine", room: String(repeating: "b", count: 32))
        )
    }

    func testRolesPresetRulesAndTheRulesSayWhatTheyAllow() {
        XCTAssertEqual(MemberRules.preset(.viewer), MemberRules())
        XCTAssertTrue(MemberRules.preset(.member).canPostEvents)
        XCTAssertFalse(MemberRules.preset(.member).canEditGovernance)
        XCTAssertTrue(MemberRules.preset(.admin).canEditGovernance)
        XCTAssertEqual(MemberRules().summary, L("view only"))
        XCTAssertEqual(MemberRules.preset(.admin).summary, "\(L("governance")) · \(L("hand-off")) · \(L("posts")) · \(L("chats"))")
        XCTAssertTrue(MemberHubPolicy.allows("project.policy.set", rules: .preset(.admin)))
        XCTAssertFalse(MemberHubPolicy.allows("project.policy.set", rules: .preset(.member)))
        XCTAssertTrue(MemberHubPolicy.allows("mesh.event", rules: .preset(.member)))
        XCTAssertTrue(MemberHubPolicy.allows("user.message", rules: .preset(.admin)), "a member may write into the Project's chats")
        XCTAssertFalse(MemberHubPolicy.allows("user.message", rules: .preset(.viewer)), "a viewer changes nothing")
        XCTAssertFalse(MemberHubPolicy.allows("approval.decision", rules: .preset(.admin)), "approvals never leave the owner's phone")
        for type in ["project.policy.set", "mesh.handoff.prepare", "mesh.event", "user.message"] {
            XCTAssertFalse(MemberHubPolicy.refusal(type).isEmpty)
        }
        for role in MemberRole.allCases {
            XCTAssertFalse(role.title.isEmpty)
            XCTAssertFalse(role.explanation.isEmpty)
        }
    }

    func testALinkKnowsWhetherItIsWaitingConnectedOrGone() throws {
        let waiting = try link(rules: .preset(.viewer))
        XCTAssertEqual(waiting.state(now: 2_000, connected: false), .waiting(expiresAt: waiting.inviteExpiresAt))
        XCTAssertEqual(waiting.state(now: waiting.inviteExpiresAt + 1, connected: false), .expired)
        XCTAssertEqual(waiting.state(now: 2_000, connected: true), .connected)
        var joined = try link(rules: .preset(.viewer), joined: true)
        joined.lastSeenAt = 3_000
        XCTAssertEqual(joined.state(now: 9_000, connected: false), .offline(lastSeenAt: 3_000))
        XCTAssertFalse(MemberLinkPresentation.stateLabel(.expired).isEmpty)
        XCTAssertFalse(MemberLinkPresentation.stateLabel(.waiting(expiresAt: 0)).isEmpty)
        XCTAssertFalse(MemberLinkPresentation.stateLabel(.offline(lastSeenAt: nil)).isEmpty)
        XCTAssertFalse(MemberLinkPresentation.stateLabel(.offline(lastSeenAt: 3_000)).isEmpty)
    }

    func testLinksSurviveARelaunchInTheKeychain() throws {
        let stored = [try link(rules: .preset(.admin))]
        XCTAssertTrue(MemberLinkStore.save(stored, service: service))
        XCTAssertEqual(MemberLinkStore.load(service: service), stored)
        MemberLinkStore.remove(service: service)
        XCTAssertEqual(MemberLinkStore.load(service: service), [])
    }

    func testAnInviteParksTheOtherPhonesHalfAndKeepsThisOnes() async throws {
        let model = AppModel()
        model.memberLinks = []
        let mac = try pairing()
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: mac, mode: .add, prefer: true)
        model.meshSnapshots = ["project": snapshot()]
        var parkedBody = Data()
        var parkedPath = ""
        let invite = try await model.createMemberInvite(
            projectId: "project", name: "  Olga ", role: .admin, rules: .preset(.admin)
        ) { request, body in
            XCTAssertEqual(request.httpMethod, "PUT")
            parkedPath = request.url?.path ?? ""
            parkedBody = body
            return 201
        }
        defer {
            model.meshEndpointRelaysById.values.forEach { $0.disconnect() }
            model.memberLinks = []
        }
        XCTAssertTrue(parkedPath.hasPrefix("/pair/"))
        let secure = try XCTUnwrap(Pairing.secureLink(fromURI: invite), "the other phone's pairing sheet reads it")
        XCTAssertEqual("/pair/\(secure.mailboxId)", parkedPath)
        let sealed = try JSONDecoder().decode(Crypto.SealResult.self, from: parkedBody)
        let opened = try XCTUnwrap(Crypto.openWithTransferKey(nonceB64: sealed.nonce, boxB64: sealed.box, key: secure.transferKey))
        let theirs = try JSONDecoder().decode(Pairing.self, from: opened)
        let link = try XCTUnwrap(model.memberLinks.first)
        XCTAssertEqual(theirs.role, "phone")
        XCTAssertEqual(theirs.room, link.id)
        XCTAssertEqual(theirs.peerPublicKey, link.hubPairing.myPublicKey)
        XCTAssertEqual(theirs.myPublicKey, link.hubPairing.peerPublicKey)
        XCTAssertTrue(theirs.deviceName.contains("GrantTap"))
        XCTAssertEqual(link.hubPairing.role, "machine")
        XCTAssertEqual(link.name, "Olga")
        XCTAssertFalse(String(decoding: parkedBody, as: UTF8.self).contains(link.hubPairing.mySecretKey), "nothing of this phone's is parked")
        XCTAssertNotNil(model.meshEndpointRelaysById[link.id], "this phone speaks to the member as a computer would")
        XCTAssertTrue(model.meshProjectSourceRooms["project"]?.contains(link.id) == true, "the Project is forwarded there")
        XCTAssertFalse(model.computerRooms(for: "project").contains(link.id), "but a policy is never sent there")
        XCTAssertEqual(MemberLinkStore.load().first?.id, link.id)
        model.removeMemberLink(id: link.id)
        XCTAssertNil(model.meshEndpointRelaysById[link.id])
        XCTAssertTrue(MemberLinkStore.load().isEmpty)

        await XCTAssertThrowsErrorAsync(try await model.createMemberInvite(projectId: "nope", name: "", role: .viewer, rules: .preset(.viewer)) { (_: URLRequest, _: Data) in 201 })
        await XCTAssertThrowsErrorAsync(try await model.createMemberInvite(projectId: "project", name: "", role: .viewer, rules: .preset(.viewer)) { (_: URLRequest, _: Data) in 500 })
        model.connectionRegistry = .empty
        await XCTAssertThrowsErrorAsync(try await model.createMemberInvite(projectId: "project", name: "", role: .viewer, rules: .preset(.viewer)) { (_: URLRequest, _: Data) in 201 })
    }

    func testTheComputerSideOfARoomHearsThePhoneAndHandsItToTheRules() throws {
        let hub = try NaclBox.keyPair()
        let member = try NaclBox.keyPair()
        let room = String(repeating: "c", count: 32)
        let hubPairing = Pairing(
            relayUrl: "wss://relay.granttap.app", room: room, role: "machine", deviceName: "Hub", senderId: "hub",
            myPublicKey: hub.publicKey.base64EncodedString(), mySecretKey: hub.secretKey.base64EncodedString(),
            peerPublicKey: member.publicKey.base64EncodedString()
        )
        let client = RelayClient(pairing: hubPairing)
        XCTAssertEqual(client.role, Role.machine)
        XCTAssertEqual(client.peerRole, Role.phone)
        var heard: [String] = []
        client.onHubPayload = { type, _ in heard.append(type) }
        let plain = try JSONEncoder().encode(["type": "user.message"])
        let sealed = try Crypto.seal(plain, theirPublicKeyB64: hubPairing.myPublicKey, mySecretKeyB64: member.secretKey.base64EncodedString())
        let toMachine = Envelope(room: room, from: .phone, to: "machine", senderId: "phone", deliveryId: "1", nonce: sealed.nonce, box: sealed.box)
        client.handle(String(decoding: try JSONEncoder().encode(toMachine), as: UTF8.self))
        var toPhone = toMachine
        toPhone.to = "phone"
        toPhone.deliveryId = "2"
        client.handle(String(decoding: try JSONEncoder().encode(toPhone), as: UTF8.self))
        var fromMachine = toMachine
        fromMachine.from = .machine
        fromMachine.deliveryId = "3"
        client.handle(String(decoding: try JSONEncoder().encode(fromMachine), as: UTF8.self))
        XCTAssertEqual(heard, ["user.message"], "only what a phone sends to the computer side is heard")
        XCTAssertEqual(Payloads.hello("x", role: .machine).role, Role.machine)
        XCTAssertEqual(Payloads.hello("x").role, Role.phone)
    }

    func testAMembersEditIsForwardedOrRefusedByItsRules() throws {
        let model = AppModel()
        model.memberLinks = []
        let mac = try pairing()
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: mac, mode: .add, prefer: true)
        model.meshProjectSourceRooms["project"] = [mac.room]
        let viewer = try link(rules: .preset(.viewer))
        model.memberLinks = [viewer]
        let policy = ProjectGovernanceLogic.updatedPolicy(
            current: nil, projectId: "project", enforcement: .bestAvailable, defaults: [.shell: .allow], createdBy: "member"
        )
        let set = ProjectPolicySet(
            type: "project.policy.set", sessionId: "project", projectId: "project",
            expectedRevision: 0, policy: policy, createdAt: 5
        )
        let data = try JSONEncoder().encode(set)
        XCTAssertTrue(ProjectGovernanceWireValidator.validSet(data))
        model.handleMemberPayload(type: "project.policy.set", data: data, linkId: viewer.id)
        XCTAssertTrue(model.memberForwardedSets.isEmpty, "a viewer's edit goes nowhere")
        XCTAssertNotNil(model.memberLinks.first?.lastSeenAt, "but the phone was heard")

        var admin = viewer
        admin.rules = .preset(.admin)
        model.memberLinks = [admin]
        model.handleMemberPayload(type: "project.policy.set", data: data, linkId: admin.id)
        XCTAssertEqual(model.memberForwardedSets["project:1"], admin.id, "an admin's edit is forwarded to the computers, remembered by revision")
        // Another Project's edit through this link is not this link's to make.
        var foreign = set
        foreign = ProjectPolicySet(type: "project.policy.set", sessionId: "other", projectId: "other", expectedRevision: 0,
                                   policy: ProjectGovernanceLogic.updatedPolicy(current: nil, projectId: "other", enforcement: .bestAvailable, defaults: [:], createdBy: "m"), createdAt: 5)
        model.handleMemberPayload(type: "project.policy.set", data: try JSONEncoder().encode(foreign), linkId: admin.id)
        XCTAssertNil(model.memberForwardedSets["other:1"])
        // The computer's answer to that edit goes back to the member, not onto this screen.
        model.meshEndpointRelaysById[admin.id] = RelayClient(pairing: admin.hubPairing)
        let rejected = ProjectPolicyRejected(type: "project.policy.rejected", sessionId: "project", projectId: "project",
                                             expectedRevision: 0, currentRevision: 1, reason: "revision_mismatch", detail: nil, generatedAt: 6)
        XCTAssertTrue(model.handOffRejectionToMember(rejected))
        XCTAssertTrue(model.memberForwardedSets.isEmpty)
        XCTAssertFalse(model.handOffRejectionToMember(rejected), "handed off once")
        model.handleMemberPayload(type: "user.message", data: Data("{}".utf8), linkId: admin.id)
        model.handleMemberPayload(type: "mesh.event", data: Data("{}".utf8), linkId: admin.id)
        model.memberLinks = []
    }

    func testAProjectionBecomesTheStatusAMemberIsHanded() throws {
        let policy = ProjectGovernanceLogic.updatedPolicy(
            current: nil, projectId: "project", enforcement: .strict, defaults: [.mcp: .ask], createdBy: "phone"
        )
        let projection = ProjectGovernanceProjection(
            projectId: "project", revision: 1, enforcement: .strict, rules: [],
            coverage: [
                ProjectPolicyCoverageSummary(endpointId: "Mac", provider: "claude", capability: "mcp", status: .enforced),
                ProjectPolicyCoverageSummary(endpointId: "Mac", provider: "claude", capability: "shell", status: .observed),
                ProjectPolicyCoverageSummary(endpointId: "Mac", provider: "claude", capability: "nonsense", status: .unknown),
            ],
            updatedAt: 7, requiredCapabilities: [.mcp], strictReady: true, policy: policy
        )
        let status = try XCTUnwrap(projection.wireStatus(now: 8))
        XCTAssertTrue(ProjectGovernanceWireValidator.validStatus(status))
        XCTAssertEqual(status.coverage.endpoints.first?.capabilities.count, 2, "a kind the wire does not know is left out")
        XCTAssertNil(ProjectGovernanceProjection(projectId: "p", revision: 0, enforcement: .bestAvailable, rules: [], coverage: [], updatedAt: 1).wireStatus())
    }

    func testTheScreensRender() throws {
        let model = AppModel()
        model.memberLinks = [try link(rules: .preset(.member), joined: true)]
        model.meshSnapshots = ["project": snapshot()]
        RenderProbe.render(NavigationView { ProjectMembersView(snapshot: snapshot(), model: model) })
        RenderProbe.render(NavigationView { MemberLinkDetailView(linkId: model.memberLinks[0].id, model: model) })
        RenderProbe.render(NavigationView { MemberLinkDetailView(linkId: "gone", model: model) })
        RenderProbe.render(MemberInviteSheet(projectId: "project", model: model))
        RenderProbe.render(QRCodeImage(text: "granttap://pair-v2?v=2&u=https://relay.granttap.app&m=x&k=y"))
        XCTAssertNotNil(QRCodeImage.image(for: "hello"))
        model.memberLinks = []
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T, file: StaticString = #filePath, line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("expected an error", file: file, line: line)
    } catch {}
}
