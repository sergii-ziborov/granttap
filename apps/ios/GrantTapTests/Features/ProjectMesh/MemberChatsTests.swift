import SwiftUI
import TweetNacl
import XCTest
@testable import GrantTap

/// A Project shared with a person shares its chats too, by the rules the
/// owner set: what the hub hands over, what it takes back, and what it
/// refuses.
@MainActor
final class MemberChatsTests: XCTestCase {
    private let own = String(repeating: "a", count: 32)
    private let hubRoom = String(repeating: "h", count: 32)
    private let linkRoom = String(repeating: "b", count: 32)

    override func setUp() {
        super.setUp()
        // A merged snapshot is written to disk, and a model built later in
        // another test process would restore it as its own.
        ProjectMeshPersistence.clear()
    }

    override func tearDown() {
        MemberLinkStore.remove()
        ProjectMeshPersistence.clear()
        super.tearDown()
    }

    private func pairing(role: String, room: String, hub: Bool? = nil) throws -> Pairing {
        try MemberHubFixture.pairing(role: role, room: room, hub: hub)
    }

    private func session(_ id: String, project: String?) -> SessionInfo {
        MemberHubFixture.session(id, project: project)
    }

    private func snapshot(_ projectId: String = "project") -> ProjectMeshSnapshot {
        MemberHubFixture.snapshot(projectId)
    }

    private func hub(rules: MemberRules = .preset(.member)) throws -> (AppModel, MemberLink) {
        try MemberHubFixture.hub(rules: rules)
    }

    func testRulesGrowChatsAndOldLinksDecodeWithThemOff() throws {
        XCTAssertTrue(MemberRules.preset(.member).canSeeChats)
        XCTAssertTrue(MemberRules.preset(.member).canSendToChats)
        XCTAssertTrue(MemberRules.preset(.admin).canSendToChats)
        XCTAssertFalse(MemberRules.preset(.viewer).canSeeChats)
        let stored = try JSONDecoder().decode(MemberRules.self, from: Data(#"{"canEditGovernance":true,"canHandOffTasks":true,"canPostEvents":true}"#.utf8))
        XCTAssertTrue(stored.canEditGovernance)
        XCTAssertFalse(stored.canSeeChats, "a link from before chats were shared shares none")
        XCTAssertFalse(stored.canSendToChats)
        XCTAssertEqual(MemberRules(canSeeChats: true).summary, L("reads chats"))
        XCTAssertEqual(MemberRules(canSeeChats: true, canSendToChats: true).summary, L("chats"))
        XCTAssertTrue(MemberHubPolicy.allows("session.events", rules: MemberRules(canSeeChats: true)))
        XCTAssertFalse(MemberHubPolicy.allows("session.control", rules: MemberRules(canSeeChats: true)))
        XCTAssertTrue(MemberHubPolicy.allows("mesh.snapshot", rules: .preset(.member)))
        XCTAssertTrue(MemberHubPolicy.allowsEvent("TASK_PROGRESS", rules: .preset(.viewer)))
        XCTAssertFalse(MemberHubPolicy.allowsEvent("HANDOFF_REQUEST", rules: MemberRules(canPostEvents: true)))
        XCTAssertTrue(MemberHubPolicy.allowsEvent("HANDOFF_REQUEST", rules: .preset(.member)))
        for type in ["user.message", "session.events", "mesh.snapshot", "nonsense"] {
            XCTAssertFalse(MemberHubPolicy.refusal(type).isEmpty)
        }
        // Writing without seeing is nothing; seeing is implied by writing.
        let link = MemberLink(id: "x", projectId: "p", name: "n", role: .member, rules: .preset(.member),
                              createdAt: 1, inviteExpiresAt: 2, hubPairing: try pairing(role: "machine", room: linkRoom))
        XCTAssertFalse(MemberLinkEdits.withChats(link, false).rules.canSendToChats)
        XCTAssertTrue(MemberLinkEdits.withChatWriting(MemberLinkEdits.withChats(link, false), true).rules.canSeeChats)
        XCTAssertEqual(MemberRole.member.explanation.isEmpty, false)
    }

    func testTheHubHandsAMemberOnlyTheProjectsChatsOnItsOwnComputers() throws {
        let (model, link) = try hub()
        var entries: [ActivityEntry] = []
        for index in 0..<50 { entries.append(ActivityEntry(id: "e\(index)", kind: "message", text: "row \(index)", createdAt: Double(index))) }
        model.activities["s1"] = SessionActivity(type: "session.activity", sessionId: "s1", agent: "claude", state: "idle",
                                                 entries: entries, generatedAt: 1)
        let status = model.memberSessionsStatus(projectId: "project", now: 9)
        XCTAssertEqual(status.sessions.map(\.sessionId), ["s1"], "not another Project's chat, not a chat that came from someone else's phone")
        XCTAssertEqual(status.history.map(\.sessionId), ["h1"])
        XCTAssertEqual(status.activities.count, 1)
        XCTAssertEqual(status.activities[0].entries.count, AppModel.memberTranscriptEntries, "a first look, not the whole transcript")
        XCTAssertEqual(status.activities[0].entries.first?.id, "e10")
        XCTAssertEqual(status.machine, model.hubDisplayName)
        XCTAssertEqual(status.generatedAt, 9)
        XCTAssertTrue(model.memberSessionsStatus(projectId: "project", includeTranscripts: false).activities.isEmpty)
        XCTAssertTrue(model.memberSessionsStatus(projectId: "nowhere").sessions.isEmpty)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(status)) as? [String: Any])
        XCTAssertEqual(encoded["type"] as? String, "sessions.status")

        XCTAssertEqual(model.chatWatchers(for: "project").map(\.id), [link.id])
        model.memberLinkConnected.remove(link.id)
        XCTAssertTrue(model.chatWatchers(for: "project").isEmpty, "a member who is not here is not handed anything")
        model.memberLinkConnected.insert(link.id)
        // The hand-over and the running forwards run without a socket, and only for own computers.
        model.forwardChatsToMember(link)
        model.forwardStatusToMembers(fromRoom: own)
        model.forwardStatusToMembers(fromRoom: hubRoom)
        XCTAssertEqual(model.forwardChatPayload(status.activities[0], sessionId: "s1", fromRoom: own), 1)
        XCTAssertEqual(model.forwardChatPayload(status.activities[0], sessionId: "s3", fromRoom: hubRoom), 0, "what came from someone else's phone is not re-shared")
        XCTAssertEqual(model.forwardChatPayload(status.activities[0], sessionId: "s2", fromRoom: own), 0, "another Project has no watcher here")
        model.forwardAgentEventToMembers(AgentEvent(type: "agent.event", text: "done", kind: "response", sessionId: "s1", createdAt: 1), fromRoom: own)
        model.forwardAgentEventToMembers(AgentEvent(type: "agent.event", text: "done", kind: "status", createdAt: 1), fromRoom: nil)
        model.forwardActivityToMembers(status.activities[0], fromRoom: own)
        // A viewer sees nothing, and is handed nothing when the rule is switched on for another.
        model.updateMemberLink(MemberLinkEdits.withRole(link, .viewer))
        XCTAssertTrue(model.chatWatchers(for: "project").isEmpty)
        model.updateMemberLink(MemberLinkEdits.withChats(link, true))
        XCTAssertEqual(model.chatWatchers(for: "project").count, 1)
    }

    func testAMembersMessageGoesToTheChatsComputerAndItsReceiptComesBack() throws {
        let (model, link) = try hub()
        let message = Payloads.message("Run the tests", messageId: "m-1", agent: nil, cwd: nil, sessionId: "s1", requestId: nil)
        model.handleMemberPayload(type: "user.message", data: try JSONEncoder().encode(message), linkId: link.id)
        XCTAssertEqual(model.memberForwardedMessages["m-1"], link.id, "on to the computer that owns the chat")
        // Another Project's chat, a chat from someone else's phone, a chat nobody knows: refused, with a receipt.
        for sessionId in ["s2", "s3", "nope"] {
            let foreign = Payloads.message("Hi", messageId: "m-\(sessionId)", agent: nil, cwd: nil, sessionId: sessionId, requestId: nil)
            XCTAssertFalse(model.forwardMemberMessage(try JSONEncoder().encode(foreign), link: link))
            XCTAssertNil(model.memberForwardedMessages["m-\(sessionId)"])
        }
        let newChat = Payloads.message("Start", messageId: "m-new", agent: "claude", cwd: "/repo", sessionId: nil, requestId: nil)
        XCTAssertFalse(model.forwardMemberMessage(try JSONEncoder().encode(newChat), link: link), "a member writes into the Project's chats, not new ones on someone else's computer")
        XCTAssertFalse(model.forwardMemberMessage(Data("{}".utf8), link: link))

        // The computer's receipt goes to the member, not into this outbox.
        let accepted = DeliveryReceipt(type: "delivery.receipt", messageId: "M-1", status: "accepted", receivedAt: 2)
        model.receive(accepted, fromRoom: own)
        XCTAssertNil(model.memberForwardedMessages["m-1"], "settled")
        XCTAssertFalse(model.handOffReceiptToMember(accepted), "handed off once")
        model.memberForwardedMessages["m-2"] = link.id
        XCTAssertTrue(model.handOffReceiptToMember(DeliveryReceipt(type: "delivery.receipt", messageId: "m-2", status: "processing", receivedAt: 3)))
        XCTAssertEqual(model.memberForwardedMessages["m-2"], link.id, "still open until the computer settles it")

        // A viewer's message is refused outright.
        let (viewerModel, viewer) = try hub(rules: .preset(.viewer))
        viewerModel.handleMemberPayload(type: "user.message", data: try JSONEncoder().encode(message), linkId: viewer.id)
        XCTAssertTrue(viewerModel.memberForwardedMessages.isEmpty)
    }

    func testChatControlsFollowTheChatAndAHandoffIsAuthorisedLikeThisPhonesOwn() throws {
        let (model, link) = try hub()
        let control = Data(#"{"type":"session.control","sessionId":"s1","action":"pause","createdAt":1}"#.utf8)
        XCTAssertTrue(model.forwardMemberChatControl(type: "session.control", data: control, link: link))
        let elsewhere = Data(#"{"type":"session.control","sessionId":"s2","action":"pause","createdAt":1}"#.utf8)
        XCTAssertFalse(model.forwardMemberChatControl(type: "session.control", data: elsewhere, link: link))
        let events = Data(#"{"type":"session.events","sessionId":"s1","createdAt":1}"#.utf8)
        XCTAssertTrue(model.forwardMemberChatControl(type: "session.events", data: events, link: link))
        let subscribe = Data(#"{"type":"session.subscribe","sessionId":"s1","active":true,"createdAt":1}"#.utf8)
        XCTAssertTrue(model.forwardMemberChatControl(type: "session.subscribe", data: subscribe, link: link))
        XCTAssertFalse(model.forwardMemberChatControl(type: "sessions.refresh", data: Data("{}".utf8), link: link))
        model.handleMemberPayload(type: "sessions.refresh", data: Data(#"{"type":"sessions.refresh","createdAt":1}"#.utf8), linkId: link.id)
        model.handleMemberPayload(type: "session.control", data: control, linkId: link.id)
        // The computer's word on a pause a member asked for goes to that member.
        XCTAssertEqual(model.memberForwardedControls["s1"], link.id)
        let answer = SessionControlResult(type: "session.control.result", sessionId: "s1", action: "pause",
                                          ok: true, message: "Paused.", createdAt: 2)
        model.receive(answer)
        XCTAssertNil(model.memberForwardedControls["s1"], "answered once, to the phone that asked")
        XCTAssertFalse(model.handOffControlResultToMember(answer))
        XCTAssertEqual(model.sessions.first(where: { $0.sessionId == "s1" })?.isPaused, true)

        let prepare = ProjectMeshHandoffPrepare(
            type: "mesh.handoff.prepare", sessionId: "s1", projectId: "project", taskId: "task-project",
            targetProvider: "codex", targetComputer: "Air", createdAt: 1
        )
        model.handleMemberPayload(type: "mesh.handoff.prepare", data: try JSONEncoder().encode(prepare), linkId: link.id)
        XCTAssertEqual(model.authorizedHandoffRoutes["task-project"], AppModel.handoffRoute(provider: "codex", computer: "Air"),
                       "the request the computer publishes goes on to its destination without waiting for a person")
        let foreign = ProjectMeshHandoffPrepare(
            type: "mesh.handoff.prepare", sessionId: "s2", projectId: "other", taskId: "task-other",
            targetProvider: "codex", targetComputer: "Air", createdAt: 1
        )
        XCTAssertFalse(model.forwardMemberHandoff(try JSONEncoder().encode(foreign), link: link))
        XCTAssertNil(model.authorizedHandoffRoutes["task-other"])
        XCTAssertFalse(model.forwardMemberHandoff(Data("{}".utf8), link: link))
    }

    func testAMembersEventsAndSnapshotsStayInsideTheirProject() throws {
        let (model, link) = try hub()
        func event(_ id: String, source: String, type: String = "TASK_PROGRESS", project: String = "project") throws -> Data {
            try JSONEncoder().encode(ProjectMeshEvent(
                type: "mesh.event", sessionId: "task-\(project)", eventId: id, projectId: project, taskId: "task-\(project)",
                sourceSessionId: source, eventType: type, createdAt: 1, expiresAt: nil,
                payload: ProjectMeshEventPayload(summary: "Working")
            ))
        }
        XCTAssertFalse(model.acceptMemberEvent(try event("as-owner", source: "s1"), link: link),
                       "a chat on this phone's own computer is never spoken for by a member")
        XCTAssertTrue(model.acceptMemberEvent(try event("own-chat", source: "member-chat"), link: link))
        XCTAssertFalse(model.acceptMemberEvent(try event("elsewhere", source: "member-chat", project: "other"), link: link))
        XCTAssertFalse(model.acceptMemberEvent(Data("{}".utf8), link: link))
        model.handleMemberPayload(type: "mesh.event", data: try event("through-rules", source: "member-chat"), linkId: link.id)
        XCTAssertTrue(model.meshSnapshots["project"]?.events.contains { $0.eventId == "through-rules" } == true)

        // A member's own computer joins the mesh through the member's phone.
        XCTAssertTrue(model.acceptMemberSnapshot(try JSONEncoder().encode(snapshot()), link: link))
        XCTAssertTrue(model.meshProjectSourceRooms["project"]?.contains(link.id) == true)
        XCTAssertFalse(model.acceptMemberSnapshot(try JSONEncoder().encode(snapshot("other")), link: link))
        model.handleMemberPayload(type: "mesh.snapshot", data: try JSONEncoder().encode(snapshot()), linkId: link.id)
        XCTAssertTrue(model.isOwnComputerChat("s1", projectId: "project"))
        XCTAssertFalse(model.isOwnComputerChat("s3", projectId: "project"))
    }

    func testAnEditIsAnsweredByItsName() throws {
        XCTAssertEqual(AppModel.policyEditKey(projectId: "project", revision: 1, requestId: nil), "project:1")
        XCTAssertEqual(AppModel.policyEditKey(projectId: "project", revision: 1, requestId: " "), "project:1")
        XCTAssertEqual(AppModel.policyEditKey(projectId: "project", revision: 1, requestId: "r-1"), "req:r-1")
        let (model, link) = try hub(rules: .preset(.admin))
        let policy = ProjectGovernanceLogic.updatedPolicy(
            current: nil, projectId: "project", enforcement: .bestAvailable, defaults: [.shell: .allow], createdBy: "member"
        )
        let set = ProjectPolicySet(type: "project.policy.set", sessionId: "project", projectId: "project",
                                   expectedRevision: 0, policy: policy, requestId: "r-1", createdAt: 5)
        model.handleMemberPayload(type: "project.policy.set", data: try JSONEncoder().encode(set), linkId: link.id)
        XCTAssertEqual(model.memberForwardedSets["req:r-1"], link.id)
        XCTAssertNil(model.memberForwardedSets["project:1"], "named, so another member's edit of the same revision keeps its own answer")
        let rejected = ProjectPolicyRejected(type: "project.policy.rejected", sessionId: "project", projectId: "project",
                                             expectedRevision: 0, currentRevision: 1, reason: "revision_mismatch",
                                             requestId: "r-1", generatedAt: 6)
        XCTAssertTrue(model.handOffRejectionToMember(rejected))
        XCTAssertTrue(model.memberForwardedSets.isEmpty)
        let decoded = try JSONDecoder().decode(ProjectPolicyRejected.self, from: JSONEncoder().encode(rejected))
        XCTAssertEqual(decoded.requestId, "r-1")
    }

    func testAJoinedProjectSaysWhoSharesItAndTheJoinSheetSaysWhatItDoes() throws {
        let (model, _) = try hub()
        let theirs = try XCTUnwrap(model.connectionRegistry.connections.first { $0.id == hubRoom })
        XCTAssertTrue(theirs.pairing.isHub)
        let decoded = try JSONDecoder().decode(Pairing.self, from: JSONEncoder().encode(theirs.pairing))
        XCTAssertTrue(decoded.isHub)
        XCTAssertFalse(try JSONDecoder().decode(Pairing.self, from: Data(#"{"relayUrl":"wss://r","room":"x","role":"phone","deviceName":"Mac","senderId":"s","myPublicKey":"a","mySecretKey":"b","peerPublicKey":"c"}"#.utf8)).isHub)
        XCTAssertTrue(model.isHubRoom(hubRoom))
        XCTAssertFalse(model.isHubRoom(own))
        XCTAssertEqual(model.ownComputerRooms(for: "project"), [own])

        let rows = model.projectListRows
        XCTAssertEqual(rows.first { $0.projectId == "project" }?.sharedBy, theirs.displayName)
        XCTAssertNil(rows.first { $0.projectId == "other" }?.sharedBy)
        XCTAssertEqual(ProjectsCatalog.sharedBy("project", rooms: ["project": [own]], connections: model.connectionRegistry.connections), nil)
        RenderProbe.render(ProjectListRowView(row: rows.first { $0.projectId == "project" }!))
        RenderProbe.render(NavigationView { ProjectMembersView(snapshot: snapshot(), model: model) })
        RenderProbe.render(PairingSheet(purpose: .joinProject).environmentObject(model))
        RenderProbe.render(SettingsConnectionSection(onPair: {}, onForgetAll: {}).environmentObject(model))
        XCTAssertEqual(PairingPurpose.joinProject.title, L("Join a Project"))
        XCTAssertEqual(PairingPurpose.computer.title, L("Add computer"))
        XCTAssertNotEqual(PairingPurpose.joinProject.scanExplanation, PairingPurpose.computer.scanExplanation)
        RenderProbe.render(NavigationView { ProjectsTabView(model: model) })
        RenderProbe.render(MemberInviteSheet(projectId: "project", model: model))
        RenderProbe.render(NavigationView { MemberLinkDetailView(linkId: linkRoom, model: model) })
    }
}
