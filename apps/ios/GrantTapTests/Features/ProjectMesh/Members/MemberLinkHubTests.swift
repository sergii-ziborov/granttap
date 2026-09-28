import SwiftUI
import TweetNacl
import XCTest
@testable import GrantTap

/// The hub side of a link: a member coming and going, what is forwarded to
/// them while they are here, the sheet that makes an invite, and the words a
/// role is written in.
extension MemberLinkTests {
    func testCompanyAccountGrantSurvivesAKeychainReload() {
        let service = "com.ziborov.granttap.company-accounts.tests"
        defer { CompanyAccountStore.remove(service: service) }
        let accounts = [CompanyAccount(
            id: "person", name: "Olga", repositoryAccess: .selected(["repo-a", "repo-b"])
        )]
        XCTAssertTrue(CompanyAccountStore.save(accounts, service: service))
        XCTAssertEqual(CompanyAccountStore.load(service: service), accounts)
    }

    func testCompanyRepositoryGrantAndMeshMembershipAreIndependent() throws {
        var project = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "p", projectId: "p",
            project: ProjectMeshProject(projectId: "p", name: "Project", canonicalRepositoryId: "repo-a", createdAt: 1),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1
        )
        project.bindings = [ProjectBindingSummary(
            bindingId: "b", projectId: "p", endpointId: "mac", repositoryId: "repo-b",
            displayName: "B", available: true
        )]
        let account = CompanyAccount(id: "person", name: "Olga", repositoryAccess: .selected(["repo-a"]))
        XCTAssertFalse(CompanyAccountPolicy.canReceive(project, account: account), "a partial grant cannot expose the whole Mesh snapshot")
        var expanded = account
        expanded.repositoryAccess = .selected(["repo-a", "repo-b"])
        XCTAssertTrue(CompanyAccountPolicy.canReceive(project, account: expanded))
        expanded.repositoryAccess = .all
        XCTAssertTrue(CompanyAccountPolicy.canReceive(project, account: expanded))
        expanded.disabled = true
        XCTAssertFalse(CompanyAccountPolicy.canReceive(project, account: expanded))
    }

    func testAccountGrantDoesNotCreateMeshMembershipAndRevocationStopsForwarding() throws {
        let (model, legacy) = try hubModel()
        defer {
            model.meshEndpointRelaysById.values.forEach { $0.disconnect() }
            _ = model.removeMemberLink(id: legacy.id)
        }
        model.companyAccounts = []
        let created = try XCTUnwrap(model.createCompanyAccount(name: "Olga"))
        XCTAssertFalse(CompanyAccountPolicy.canReceive(model.meshSnapshots["project"]!, account: created))
        XCTAssertTrue(model.assignCompanyAccount(created.id, to: legacy.id))
        let link = try XCTUnwrap(model.memberLinks.first)
        XCTAssertFalse(model.memberCanAccessProject(link, projectId: "project"))
        XCTAssertTrue(model.memberLinks(for: "project").isEmpty)
        var granted = created
        granted.repositoryAccess = .selected(["repo"])
        XCTAssertTrue(model.updateCompanyAccount(granted))
        XCTAssertTrue(model.memberCanAccessProject(link, projectId: "project"))
        XCTAssertEqual(model.memberLinks(for: "project").map(\.id), [link.id])
        XCTAssertFalse(model.memberCanAccessProject(link, projectId: "other"), "repository grant never joins another Mesh")
        var ungrantedContribution = model.meshSnapshots["project"]!
        ungrantedContribution.bindings = [ProjectBindingSummary(
            bindingId: "new", projectId: "project", endpointId: "other", repositoryId: "repo-b",
            displayName: "Other", available: true
        )]
        XCTAssertFalse(model.memberCanContribute(ungrantedContribution, link: link))
        granted.disabled = true
        XCTAssertTrue(model.updateCompanyAccount(granted))
        XCTAssertFalse(model.memberCanAccessProject(link, projectId: "project"))
        XCTAssertFalse(model.meshProjectSourceRooms["project"]?.contains(link.id) == true)
    }

    func testTwoDevicesCanUseOneAccountWithSeparateMeshInvites() async throws {
        let (model, original) = try hubModel()
        defer {
            model.meshEndpointRelaysById.values.forEach { $0.disconnect() }
            for link in model.memberLinks { _ = model.removeMemberLink(id: link.id) }
        }
        model.companyAccounts = []
        let account = try XCTUnwrap(model.createCompanyAccount(name: "Olga"))
        do {
            _ = try await model.createMemberInvite(
                projectId: "project", name: "Denied", role: .viewer,
                rules: .preset(.viewer), accountId: account.id, parker: { _, _ in 201 }
            )
            XCTFail("a Mesh invite cannot bypass the company repository grant")
        } catch MemberInviteError.invalidAccount {
            XCTAssertEqual(model.memberLinks.filter { $0.companyAccountId == account.id }.count, 0)
        }
        var granted = account
        granted.repositoryAccess = .selected(["repo"])
        XCTAssertTrue(model.updateCompanyAccount(granted))
        for _ in 0..<2 {
            _ = try await model.createMemberInvite(
                projectId: "project", name: "Olga's device", role: .viewer,
                rules: .preset(.viewer), accountId: account.id,
                parker: { _, _ in 201 }
            )
        }
        let accountLinks = model.memberLinks.filter { $0.companyAccountId == account.id }
        XCTAssertEqual(accountLinks.count, 2)
        XCTAssertEqual(Set(accountLinks.map(\.id)).count, 2, "each device keeps a separate revocable pairing")
        XCTAssertTrue(model.memberCanAccessProject(accountLinks[0], projectId: "project"))
        XCTAssertFalse(model.memberCanAccessProject(accountLinks[0], projectId: "other"))
        XCTAssertNil(original.companyAccountId, "existing device links need explicit account assignment")
    }

    private func hubModel() throws -> (AppModel, MemberLink) {
        let model = AppModel()
        model.memberLinks = []
        let mac = try pairingForHub()
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: mac, mode: .add, prefer: true)
        model.meshSnapshots = ["project": snapshotForHub()]
        model.meshProjectSourceRooms["project"] = [mac.room]
        let link = try linkForHub()
        model.memberLinks = [link]
        model.meshEndpointRelaysById[link.id] = RelayClient(pairing: link.hubPairing)
        model.meshEndpointRoomToId[link.id] = link.id
        model.meshProjectSourceRooms["project"]?.insert(link.id)
        return (model, link)
    }

    private func pairingForHub() throws -> Pairing {
        let me = try NaclBox.keyPair()
        let peer = try NaclBox.keyPair()
        return Pairing(
            relayUrl: "wss://relay.granttap.app", room: String(repeating: "d", count: 32), role: "phone", deviceName: "Mac", senderId: "s",
            myPublicKey: me.publicKey.base64EncodedString(), mySecretKey: me.secretKey.base64EncodedString(),
            peerPublicKey: peer.publicKey.base64EncodedString()
        )
    }

    private func snapshotForHub() -> ProjectMeshSnapshot {
        let project = ProjectMeshProject(projectId: "project", name: "GrantTap", repositoryRoot: "/repo", canonicalRepositoryId: "repo", createdAt: 1)
        return ProjectMeshSnapshot(type: "mesh.snapshot", sessionId: "project", projectId: "project", project: project,
                                   tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1)
    }

    private func linkForHub() throws -> MemberLink {
        let hub = try NaclBox.keyPair()
        let member = try NaclBox.keyPair()
        let room = String(repeating: "e", count: 32)
        let now = Date().timeIntervalSince1970 * 1_000
        return MemberLink(
            id: room, projectId: "project", name: "Olga", role: .admin, rules: .preset(.admin), createdAt: now,
            inviteExpiresAt: now + 15 * 60_000,
            hubPairing: Pairing(relayUrl: "wss://relay.granttap.app", room: room, role: "machine", deviceName: "Hub", senderId: "hub",
                                myPublicKey: hub.publicKey.base64EncodedString(), mySecretKey: hub.secretKey.base64EncodedString(),
                                peerPublicKey: member.publicKey.base64EncodedString())
        )
    }

    func testTheHubNotesAMemberComingAndGoingAndForwardsWhatItHolds() throws {
        let (model, link) = try hubModel()
        defer { model.meshEndpointRelaysById.values.forEach { $0.disconnect() }; model.memberLinks = []; MemberLinkStore.remove() }
        let policy = ProjectGovernanceLogic.updatedPolicy(current: nil, projectId: "project", enforcement: .bestAvailable, defaults: [.shell: .allow], createdBy: "phone")
        model.projectGovernance["project"] = ProjectGovernanceProjection(
            projectId: "project", revision: 1, enforcement: .bestAvailable, rules: [], coverage: [], updatedAt: 1, policy: policy
        )
        model.memberLinkConnection(up: true, linkId: link.id)
        XCTAssertTrue(model.isMemberLinkConnected(link.id))
        XCTAssertNil(model.memberLinks.first?.joinedAt, "the owner's relay socket is not the member")
        let hello = Hello(type: "hello", role: .phone, deviceName: "Olga", createdAt: Date().timeIntervalSince1970 * 1_000)
        model.handleMemberPayload(type: "hello", data: try JSONEncoder().encode(hello), linkId: link.id)
        XCTAssertNotNil(model.memberLinks.first?.joinedAt, "the paired phone's authenticated hello joins")
        XCTAssertNotNil(model.memberHubTimers[link.id], "a heartbeat keeps the member's screen live")
        model.sendHubHeartbeat(linkId: link.id)
        model.forwardProjectToMember(link)
        let status = try XCTUnwrap(model.projectGovernance["project"]?.wireStatus())
        model.forwardGovernanceStatusToMembers(status, fromRoom: model.connectionRegistry.connections[0].id)
        model.memberLinkConnection(up: false, linkId: link.id)
        XCTAssertFalse(model.isMemberLinkConnected(link.id))
        XCTAssertNil(model.memberHubTimers[link.id])
        XCTAssertNotNil(model.memberLinks.first?.lastSeenAt)
        model.memberLinkConnection(up: true, linkId: "unknown")
        // The hook a live client calls lands on the rules.
        model.attachMemberLink(link)
        model.meshEndpointRelaysById[link.id]?.onHubPayload?("user.message", Data("{}".utf8))
        model.meshEndpointRelaysById[link.id]?.onConnectionChange?(false)
        model.attachStoredMemberLinks()
        // Edits are kept.
        model.updateMemberLink(MemberLinkEdits.withRole(link, .viewer))
        XCTAssertEqual(model.memberLinks.first?.rules, MemberRules())
        model.updateMemberLink(MemberLinkEdits.withPosts(link, true))
        XCTAssertTrue(model.memberLinks.first?.rules.canPostEvents == true)
        model.updateMemberLink(MemberLinkEdits.withGovernance(link, true))
        XCTAssertTrue(model.memberLinks.first?.rules.canEditGovernance == true)
        model.updateMemberLink(MemberLinkEdits.withRole(MemberLink(id: "nope", projectId: "p", name: "x", role: .viewer, rules: .preset(.viewer), createdAt: 1, inviteExpiresAt: 2, hubPairing: link.hubPairing), .admin))
        XCTAssertEqual(model.memberLinks.count, 1)
        // An edit with no computer to apply it is refused with a reason.
        model.meshProjectSourceRooms["project"] = [link.id]
        let set = ProjectPolicySet(type: "project.policy.set", sessionId: "project", projectId: "project", expectedRevision: 0, policy: policy, createdAt: 5)
        model.handleMemberPayload(type: "project.policy.set", data: try JSONEncoder().encode(set), linkId: link.id)
        XCTAssertTrue(model.memberForwardedSets.isEmpty)
    }

    func testTheInviteSheetCreatesAndShowsTheCodeAndErrorsSpeak() async throws {
        let (model, _) = try hubModel()
        defer { model.meshEndpointRelaysById.values.forEach { $0.disconnect() }; model.memberLinks = []; MemberLinkStore.remove() }
        let sheet = MemberInviteSheet(projectId: "project", model: model) { (_: URLRequest, _: Data) in 201 }
        await sheet.performCreate()
        RenderProbe.render(sheet)
        let nodeRelay = MemberInviteSheet(projectId: "project", model: model) { (_: URLRequest, _: Data) in 200 }
        await nodeRelay.performCreate()
        RenderProbe.render(nodeRelay)
        let failing = MemberInviteSheet(projectId: "missing", model: model) { (_: URLRequest, _: Data) in 201 }
        await failing.performCreate()
        RenderProbe.render(failing)
        RenderProbe.render(MemberInviteSheet(projectId: "project", model: model, initialInvite: "granttap://pair-v2?v=2&u=https://relay.granttap.app&m=\(String(repeating: "a", count: 32))&k=k"))
        for error in [MemberInviteError.noComputer, .noProject, .keyGeneration, .relayUnavailable, .storage, .invalidLifetime] {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        }
        let beat = try JSONEncoder().encode(HubHeartbeat(machine: "Hub", createdAt: 1))
        XCTAssertTrue(String(decoding: beat, as: UTF8.self).contains("machine.heartbeat"))
        XCTAssertEqual(AppModel.base64URL(Data([251, 255, 254])), "-__-")
        XCTAssertEqual(AppModel.hex(Data([0, 255])), "00ff")
        XCTAssertFalse(MemberLinkPresentation.ago(1_000).isEmpty)
    }

    func testExpiredInviteDoesNotJoinEvenWhenTheOwnerSocketIsUp() throws {
        let (model, link) = try hubModel()
        defer { model.meshEndpointRelaysById.values.forEach { $0.disconnect() }; model.memberLinks = [] }
        model.memberLinks[0].inviteExpiresAt = Date().timeIntervalSince1970 * 1_000 - 1
        model.memberLinkConnection(up: true, linkId: link.id)
        let hello = Hello(type: "hello", role: .phone, deviceName: "Olga", createdAt: 1)
        model.handleMemberPayload(type: "hello", data: try JSONEncoder().encode(hello), linkId: link.id)
        XCTAssertNil(model.memberLinks.first?.joinedAt)
        XCTAssertEqual(model.memberLinks.first?.state(now: Date().timeIntervalSince1970 * 1_000,
                                                       connected: true), .expired)
    }

    func testLinkedProjectGrantControlsInboundPolicyScopeAndCanBeRevoked() throws {
        let (model, link) = try hubModel()
        defer { model.meshEndpointRelaysById.values.forEach { $0.disconnect() }; model.memberLinks = [] }
        var nested = snapshotForHub()
        nested = ProjectMeshSnapshot(type: nested.type, sessionId: "nested", projectId: "nested",
                                     project: .init(projectId: "nested", name: "Nested", repositoryRoot: "/nested",
                                                    canonicalRepositoryId: "repo/nested", createdAt: 1),
                                     tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1)
        model.meshSnapshots["nested"] = nested
        model.meshProjectSourceRooms["nested"] = [model.connectionRegistry.connections[0].id]
        let hello = Hello(type: "hello", role: .phone, deviceName: "Olga", createdAt: 1)
        model.handleMemberPayload(type: "hello", data: try JSONEncoder().encode(hello), linkId: link.id)
        let policy = ProjectGovernanceLogic.updatedPolicy(
            current: nil, projectId: "nested", enforcement: .bestAvailable,
            defaults: [.shell: .ask], createdBy: "member"
        )
        let set = ProjectPolicySet(type: "project.policy.set", sessionId: "nested", projectId: "nested",
                                   expectedRevision: 0, policy: policy, createdAt: 1)
        let data = try JSONEncoder().encode(set)
        model.handleMemberPayload(type: "project.policy.set", data: data, linkId: link.id)
        XCTAssertTrue(model.memberForwardedSets.isEmpty, "a related repo alone grants no access")
        var granted = try XCTUnwrap(model.memberLinks.first)
        granted.sharedProjectIds = ["project", "nested"]
        model.updateMemberLink(granted)
        XCTAssertEqual(model.memberLinks(for: "nested").map(\.id), [link.id])
        model.handleMemberPayload(type: "project.policy.set", data: data, linkId: link.id)
        XCTAssertEqual(model.memberForwardedSets["nested:1"], link.id)
        model.memberForwardedMessages["sent-to-nested"] = link.id
        model.memberForwardedControls["nested-session"] = link.id
        var revoked = try XCTUnwrap(model.memberLinks.first)
        revoked.sharedProjectIds = ["project"]
        model.updateMemberLink(revoked)
        XCTAssertTrue(model.memberLinks(for: "nested").isEmpty)
        XCTAssertTrue(model.memberForwardedSets.isEmpty, "revocation drops pending responses")
        XCTAssertTrue(model.memberForwardedMessages.isEmpty)
        XCTAssertTrue(model.memberForwardedControls.isEmpty)
        model.handleMemberPayload(type: "project.policy.set", data: data, linkId: link.id)
        XCTAssertTrue(model.memberForwardedSets.isEmpty)
    }
}

extension MemberLinkTests {
    func testARoleWordIsNotAComputersName() throws {
        let hub = try NaclBox.keyPair()
        let pairing = Pairing(
            relayUrl: "wss://relay.granttap.app", room: String(repeating: "f", count: 32), role: "phone", deviceName: "phone",
            senderId: "s", myPublicKey: hub.publicKey.base64EncodedString(), mySecretKey: hub.secretKey.base64EncodedString(),
            peerPublicKey: hub.publicKey.base64EncodedString()
        )
        var computer = LinkedComputer(id: pairing.room, pairing: pairing, label: "phone", addedAt: 1, lastCatalogAt: 0, lastMachineName: "")
        XCTAssertEqual(computer.displayName, "PC \(pairing.room.prefix(8))")
        computer.lastMachineName = "Mac.lan"
        XCTAssertEqual(computer.displayName, "Mac.lan")
        computer.label = "Office Mac"
        XCTAssertEqual(computer.displayName, "Office Mac")
        XCTAssertEqual(LinkedComputer.nameOrNothing(" Machine "), "")

        let project = ProjectMeshProject(projectId: "p", name: "P", repositoryRoot: "/r", canonicalRepositoryId: "r", createdAt: 1)
        let snapshot = ProjectMeshSnapshot(type: "mesh.snapshot", sessionId: "p", projectId: "p", project: project,
                                           tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1)
        // Every paired computer outside the Project is offered, under a real name.
        let offered = ProjectMembership.unbound(snapshot: snapshot, paired: [computer])
        XCTAssertEqual(offered.map(\.displayName), ["Office Mac"])
    }
}
