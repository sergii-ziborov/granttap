import TweetNacl
import XCTest
@testable import GrantTap

/// The second audit pass, on the phone: a member's snapshot contributes
/// only what the member may speak for, a split chat is rejoined exactly as
/// the runtime rejoins it, and a capsule may say what its checkpoint holds.
@MainActor
final class SecondPassAuditTests: XCTestCase {
    private let now = 1_800_000_000_000.0

    private struct Fixture: Decodable {
        struct Expected: Decodable {
            let tasks: [String]
            let taskId: String
            let claimTaskIds: [String]
            let dependencies: [String]
            let capsuleDependencies: [String]
            let originalCapsuleHash: String
            let capsuleHash: String
        }
        let input: ProjectMeshSnapshot
        let expected: Expected
    }

    func testAChatSplitInTwoIsRejoinedAsTheRuntimeRejoinsIt() throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(SplitChatFixture.json.utf8))
        let request = try XCTUnwrap(fixture.input.events.first { $0.eventType == "HANDOFF_REQUEST" })
        XCTAssertEqual(ProjectMeshReceiptValidator.capsuleHash(request.payload.capsule!), fixture.expected.originalCapsuleHash,
                       "the phone and the runtime name a capsule by one hash")
        let joined = ProjectMeshLogic.merged(current: nil, incoming: fixture.input, nowMs: now)
        XCTAssertEqual(joined.tasks.map(\.taskId).sorted(), fixture.expected.tasks)
        for event in joined.events {
            XCTAssertEqual(event.taskId, fixture.expected.taskId, event.eventId)
            XCTAssertEqual(event.sessionId, fixture.expected.taskId, "the scope moves with the Task: \(event.eventId)")
        }
        XCTAssertEqual(joined.claims.map(\.taskId), fixture.expected.claimTaskIds)
        XCTAssertEqual(joined.events.first { $0.eventType == "RESOURCE_CLAIM" }?.payload.claim?.taskId, fixture.expected.taskId)
        XCTAssertEqual(joined.events.first { $0.eventType == "DEPENDENCY" }?.payload.dependsOnTaskId, "task-x")
        XCTAssertEqual(joined.dependencies.map { "\($0.taskId)->\($0.dependsOnTaskId)" }, fixture.expected.dependencies,
                       "a dependency between the two halves is gone; the other keeps both ends")
        let capsule = try XCTUnwrap(joined.events.first { $0.eventType == "HANDOFF_REQUEST" }?.payload.capsule)
        XCTAssertEqual(capsule.taskId, fixture.expected.taskId)
        XCTAssertEqual(capsule.dependencies, fixture.expected.capsuleDependencies)
        XCTAssertEqual(ProjectMeshReceiptValidator.capsuleHash(capsule), fixture.expected.capsuleHash)
        let accepted = try XCTUnwrap(joined.events.first { $0.eventType == "HANDOFF_ACCEPTED" })
        let receipt = try XCTUnwrap(accepted.payload.receipt)
        XCTAssertEqual(receipt.capsuleHash, fixture.expected.capsuleHash, "the receipt names the capsule as it is now")
        XCTAssertEqual(receipt.taskId, fixture.expected.taskId)
        XCTAssertTrue(ProjectMeshReceiptValidator.valid(receipt, for: accepted, in: joined), "and still proves the handoff")
        // Nothing to rejoin leaves everything as it was.
        var apart = fixture.input
        apart.tasks = [fixture.input.tasks[0], fixture.input.tasks[2]]
        apart.executions = [fixture.input.executions[0]]
        XCTAssertEqual(ProjectMeshLogic.rejoinSplitChats(apart), apart)
    }

    private func snapshot(
        tasks: [ProjectMeshTask] = [], executions: [ExecutionSessionLink] = [], claims: [ProjectResourceClaim] = [],
        dependencies: [ProjectTaskDependency] = [], events: [ProjectMeshEvent] = [], name: String = "GrantTap",
        bindings: [ProjectBindingSummary]? = nil
    ) -> ProjectMeshSnapshot {
        ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: ProjectMeshProject(projectId: "project", name: name, repositoryRoot: "/repo", canonicalRepositoryId: "repo", createdAt: 1),
            bindings: bindings, tasks: tasks, executions: executions, claims: claims, dependencies: dependencies, events: events,
            generatedAt: 2
        )
    }

    private func task(_ id: String, owner: String?, revision: Double) -> ProjectMeshTask {
        ProjectMeshTask(taskId: id, projectId: "project", title: "T \(id)", goal: "G", state: "working",
                        ownerSessionId: owner, revision: revision, createdAt: 1, updatedAt: 1)
    }

    private func execution(_ session: String, task: String, computer: String) -> ExecutionSessionLink {
        ExecutionSessionLink(taskId: task, sessionId: session, provider: "claude", computerId: computer, workspace: "/repo", startedAt: 1)
    }

    private func event(_ id: String, source: String, type: String = "TASK_PROGRESS") -> ProjectMeshEvent {
        ProjectMeshEvent(type: "mesh.event", sessionId: "task-m", eventId: id, projectId: "project", taskId: "task-m",
                         sourceSessionId: source, eventType: type, createdAt: 1, expiresAt: nil,
                         payload: ProjectMeshEventPayload(summary: "s"))
    }

    func testAMembersSnapshotContributesOnlyWhatTheMemberMaySpeakFor() {
        let owned = MemberContribution.Owned(isOwnChat: { ["owner-chat", "owner-chat-2"].contains($0) }, ownComputers: ["MacBook"])
        let known = snapshot(tasks: [task("task-o", owner: "owner-chat", revision: 3), task("task-m", owner: "member-chat", revision: 1)])
        let incoming = snapshot(
            tasks: [
                task("task-o", owner: "member-chat", revision: 1_000_003),   // a grab at the owner's Task
                task("task-m", owner: "member-chat", revision: 2),           // the member's own, moved on
                task("task-n", owner: "member-chat-2", revision: 1),         // new, the member's
                task("task-g", owner: "owner-chat-2", revision: 9),          // handing a Task to the owner's chat
            ],
            executions: [
                execution("member-chat", task: "task-m", computer: "Air"),
                execution("owner-chat", task: "task-o", computer: "MacBook"),
                execution("stranger", task: "task-o", computer: "MacBook"),
            ],
            claims: [
                ProjectResourceClaim(claimId: "c1", projectId: "project", taskId: "task-m", ownerSessionId: "member-chat", resource: "a", mode: "claim", createdAt: 1, expiresAt: 9e12),
                ProjectResourceClaim(claimId: "c2", projectId: "project", taskId: "task-o", ownerSessionId: "owner-chat", resource: "b", mode: "claim", createdAt: 1, expiresAt: 9e12),
            ],
            dependencies: [
                ProjectTaskDependency(taskId: "task-m", dependsOnTaskId: "task-o", createdAt: 1),
                ProjectTaskDependency(taskId: "task-o", dependsOnTaskId: "task-m", createdAt: 1),
            ],
            events: [
                event("mine", source: "member-chat"),
                event("as-owner", source: "owner-chat"),
                event("handoff", source: "member-chat", type: "HANDOFF_REQUEST"),
            ],
            name: "Renamed by a member",
            bindings: [
                ProjectBindingSummary(bindingId: "b1", projectId: "project", endpointId: "MacBook", repositoryId: "repo", displayName: "repo", available: true),
                ProjectBindingSummary(bindingId: "b2", projectId: "project", endpointId: "Air", repositoryId: "repo", displayName: "repo", available: true),
            ]
        )
        let filtered = MemberContribution.filtered(incoming, known: known, rules: MemberRules(canPostEvents: true), owned: owned)
        XCTAssertEqual(filtered.tasks.map(\.taskId), ["task-m", "task-n"], "not the owner's Task, however high the revision; not a Task handed to the owner's chat")
        XCTAssertEqual(filtered.executions.map(\.sessionId), ["member-chat"], "nothing from the owner's computers, nothing in their chats' names")
        XCTAssertEqual(filtered.claims.map(\.claimId), ["c1"])
        XCTAssertEqual(filtered.dependencies.map(\.id), ["task-m\u{1f}task-o"], "only the member's Tasks depend on anything")
        XCTAssertEqual(filtered.events.map(\.eventId), ["mine"], "no event in the owner's name; no hand-off without the right")
        XCTAssertEqual(filtered.project.name, "GrantTap", "the Project stays the owner's")
        XCTAssertEqual(filtered.bindings?.map(\.endpointId), ["Air"])
        let allowed = MemberContribution.filtered(incoming, known: known, rules: .preset(.member), owned: owned)
        XCTAssertEqual(allowed.events.map(\.eventId), ["mine", "handoff"], "a member who may hand off may say so")
        // Merged, the owner's Task keeps its owner and revision.
        let merged = ProjectMeshLogic.merged(current: known, incoming: filtered, nowMs: now)
        XCTAssertEqual(merged.tasks.first { $0.taskId == "task-o" }?.ownerSessionId, "owner-chat")
        XCTAssertEqual(merged.tasks.first { $0.taskId == "task-o" }?.revision, 3)
        XCTAssertEqual(merged.tasks.first { $0.taskId == "task-m" }?.revision, 2)
        // Nothing known yet: the member's own work is taken, the owner's names still are not.
        let fresh = MemberContribution.filtered(incoming, known: nil, rules: .preset(.member), owned: owned)
        XCTAssertEqual(fresh.tasks.map(\.taskId), ["task-o", "task-m", "task-n"], "an unknown Task is the member's word until a computer of ours says otherwise")
        XCTAssertEqual(fresh.project.name, "Renamed by a member")
    }

    func testTheHubFiltersAMembersSnapshotBeforeMergingIt() throws {
        let model = AppModel()
        model.memberLinks = []
        model.agentMeshPreferences.meshEnabled = true
        let own = String(repeating: "a", count: 32)
        let me = try NaclBox.keyPair()
        let peer = try NaclBox.keyPair()
        let mac = Pairing(relayUrl: "wss://relay.granttap.app", room: own, role: "phone", deviceName: "MacBook", senderId: "s",
                          myPublicKey: me.publicKey.base64EncodedString(), mySecretKey: me.secretKey.base64EncodedString(),
                          peerPublicKey: peer.publicKey.base64EncodedString())
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: mac, mode: .add, prefer: true)
        model.sessions = [SessionInfo(sessionId: "owner-chat", agent: "claude", projectId: "project", taskId: "task-o", computerId: "MacBook",
                                      title: "Owner", state: "idle", startedAt: 1, lastActivityAt: 2, tokensSession: 1, tokensLastTurn: 1)]
        model.rememberSessionSourceRoom(own, sessionId: "owner-chat")
        model.meshProjectSourceRooms["project"] = [own]
        model.meshSnapshots["project"] = snapshot(tasks: [task("task-o", owner: "owner-chat", revision: 3)])
        let linkRoom = String(repeating: "b", count: 32)
        let link = MemberLink(id: linkRoom, projectId: "project", name: "Olga", role: .member, rules: .preset(.member), createdAt: 1,
                              inviteExpiresAt: 2, joinedAt: 1, hubPairing: Pairing(
                                relayUrl: "wss://relay.granttap.app", room: linkRoom, role: "machine", deviceName: "Hub", senderId: "h",
                                myPublicKey: me.publicKey.base64EncodedString(), mySecretKey: me.secretKey.base64EncodedString(),
                                peerPublicKey: peer.publicKey.base64EncodedString()))
        model.memberLinks = [link]
        model.meshEndpointRoomToId[linkRoom] = linkRoom
        defer { model.memberLinks = []; MemberLinkStore.remove(); ProjectMeshPersistence.clear() }
        let owned = model.ownedInProject("project")
        XCTAssertTrue(owned.isOwnChat("owner-chat"))
        XCTAssertFalse(owned.isOwnChat("member-chat"))
        XCTAssertTrue(owned.ownComputers.contains("MacBook"))
        let grab = snapshot(tasks: [task("task-o", owner: "member-chat", revision: 1_000_003), task("task-m", owner: "member-chat", revision: 1)])
        XCTAssertTrue(model.acceptMemberSnapshot(try JSONEncoder().encode(grab), link: link))
        let after = try XCTUnwrap(model.meshSnapshots["project"])
        XCTAssertEqual(after.tasks.first { $0.taskId == "task-o" }?.ownerSessionId, "owner-chat", "a member cannot take the owner's Task")
        XCTAssertEqual(after.tasks.first { $0.taskId == "task-o" }?.revision, 3)
        XCTAssertNotNil(after.tasks.first { $0.taskId == "task-m" }, "the member's own Task joined")
    }

    func testACapsuleMaySayWhatItsCheckpointHolds() throws {
        func capsuleJSON(_ checkpoint: String?) -> Data {
            let extra = checkpoint.map { ", \"checkpoint\": \($0)" } ?? ""
            return Data("""
            {"type":"mesh.event","sessionId":"task","eventId":"e","projectId":"project","taskId":"task","sourceSessionId":"chat",
             "eventType":"HANDOFF_REQUEST","createdAt":1,"payload":{"capsule":{"taskId":"task","goal":"g","currentStatus":"s",
             "sourceProvider":"claude","sourceComputer":"Mac","targetProvider":"codex","targetComputer":"Air","repository":"repo",
             "baseSha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","filesChanged":[],"dependencies":[],"resourceClaims":[],
             "remainingWork":[],"importantDecisions":[],"createdAt":1\(extra)}}}
            """.utf8)
        }
        XCTAssertTrue(ProjectMeshWireValidator.validEvent(capsuleJSON(nil)))
        XCTAssertTrue(ProjectMeshWireValidator.validEvent(capsuleJSON(#"{"status":"partial","files":3,"excluded":[".env"]}"#)))
        XCTAssertTrue(ProjectMeshWireValidator.validEvent(capsuleJSON(#"{"status":"requires_review","files":0,"excluded":[]}"#)))
        XCTAssertFalse(ProjectMeshWireValidator.validEvent(capsuleJSON(#"{"status":"whatever","files":3,"excluded":[]}"#)))
        XCTAssertFalse(ProjectMeshWireValidator.validEvent(capsuleJSON(#"{"status":"complete","files":-1,"excluded":[]}"#)))
        XCTAssertFalse(ProjectMeshWireValidator.validEvent(capsuleJSON(#"{"status":"complete","files":1,"excluded":[],"extra":1}"#)))
        XCTAssertFalse(ProjectMeshWireValidator.validEvent(capsuleJSON(#""complete""#)))
        let decoded = try JSONDecoder().decode(ProjectMeshEvent.self, from: capsuleJSON(#"{"status":"partial","files":3,"excluded":[".env"]}"#))
        let checkpoint = try XCTUnwrap(decoded.payload.capsule?.checkpoint)
        XCTAssertFalse(checkpoint.isComplete)
        XCTAssertTrue(checkpoint.summary.contains(".env"))
        XCTAssertTrue(CapsuleCheckpoint(status: "complete", files: 2, excluded: []).isComplete)
        XCTAssertFalse(CapsuleCheckpoint(status: "complete", files: 2, excluded: []).summary.isEmpty)
        XCTAssertFalse(CapsuleCheckpoint(status: "requires_review", files: 2, excluded: []).summary.isEmpty)
    }
}
