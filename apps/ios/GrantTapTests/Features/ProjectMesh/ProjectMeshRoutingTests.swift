import SwiftUI
import XCTest
@testable import GrantTap

extension ProjectMeshRuntimeTests {
    func testMeshCountsNativeIdleAsIdleAndExplainsEveryRowState() {
        let model = AppModel()
        var state = snapshot(generatedAt: now)
        state.tasks[0].ownerSessionId = "codex"
        state.executions = [execution(
            session: "codex", provider: "codex", computer: "Workstation"
        )]
        let idle = SessionInfo(
            sessionId: "codex", agent: "codex", projectId: "project", taskId: "task",
            title: "Finished locally", state: "idle", startedAt: now,
            lastActivityAt: now, tokensSession: 0, tokensLastTurn: 0
        )
        model.sessions = [idle]

        let view = ProjectMeshView(snapshot: state, model: model)
        let row = view.taskRow(state.tasks[0])

        XCTAssertEqual(view.taskCount("working"), 0)
        XCTAssertEqual(row.stateLabel, L("Idle"))
        XCTAssertEqual(row.detailLine, "\(L("Idle")) · Codex · Workstation")
    }

    func testMeshUIActionsResolveOneTaskWithoutDuplicateCards() throws {
        let model = AppModel()
        let sourcePairing = try securePairing(room: "source-ui-actions", device: "MacBook")
        let targetPairing = try securePairing(room: "target-ui-actions", device: "Workstation")
        model.connectionRegistry = ConnectionRegistry(connections: [
            linked(sourcePairing, machine: "MacBook"),
            linked(targetPairing, machine: "Workstation"),
        ], preferredId: sourcePairing.room)
        model.sessionSourceRooms["claude"] = [sourcePairing.room]
        model.sessions = [session()]

        var state = snapshot(generatedAt: now)
        state.executions.append(execution(
            session: "codex", provider: "codex", computer: "Workstation"
        ))
        state.tasks[0].ownerSessionId = "codex"
        model.meshSnapshots = ["project": state]
        let codex = SessionInfo(
            sessionId: "codex", agent: "codex", projectId: "project", taskId: "task",
            computerId: "Workstation", title: "Pairing", cwd: "/repo", branch: "tests",
            worktree: "/repo-tests", model: nil, summary: nil, accessLevel: nil,
            state: "working", startedAt: now, lastActivityAt: now + 1,
            tokensSession: 0, tokensLastTurn: 0
        )
        model.sessions = [session(), codex]
        let representativeContent = ContentView(modelOverride: model)
        XCTAssertEqual(representativeContent.activeTaskItems.compactMap(\.currentSession?.sessionId), ["codex"])
        model.activities = [
            "claude": .init(sessionId: "claude", agent: "claude", state: "idle",
                             entries: [.init(id: "source", kind: "message", text: "Done",
                                             createdAt: now)], generatedAt: now),
            "codex": .init(sessionId: "codex", agent: "codex", state: "working",
                            entries: [.init(id: "target", kind: "message", text: "Testing",
                                            createdAt: now + 1)], generatedAt: now + 1),
        ]
        let chat = TaskChatView(session: codex, modelOverride: model)
        XCTAssertEqual(chat.taskExecutionSessionIds, ["claude", "codex"])
        XCTAssertEqual(chat.taskActivityEntries.map(\.id), ["source", "target"])
        renderMeshChat(ProjectMeshView(snapshot: state, model: model))
        let sessionCard = SessionCard(session: session(), mesh: state)
        XCTAssertEqual(
            sessionCard.meshSummary,
            "2 agents · 2 computers · Claude → Codex"
        )
        XCTAssertNil(SessionCard(session: session(), mesh: snapshot(generatedAt: now)).meshSummary)

        let blocked = event(
            id: "ui-blocked", type: "TASK_BLOCKED",
            payload: .init(reason: "Choose schema", needsUser: true)
        )
        model.pendingMeshEvents = [blocked]
        let content = ContentView(modelOverride: model)
        XCTAssertEqual(content.meshSession(for: blocked)?.sessionId, "codex")
        content.openMeshTask(blocked)
        let needsYouCard = content.meshNeedsYouCard(blocked)
        needsYouCard.onOpen()
        needsYouCard.onDismiss()
        XCTAssertEqual(model.pendingMeshEvents, [blocked])
        XCTAssertEqual(model.meshAttentionStates[blocked.eventId]?.status, .acknowledged)

        let handoff = TaskHandoffSheet(session: session(), model: model)
        _ = handoff.computerOptions
        _ = handoff.agentOptions
        handoff.applyDefaults()
        handoff.submitHandoff()

        let controls = ChatCapabilitySheet(
            sessionId: "claude", session: session(), rows: [],
            accent: .blue, model: model, onToggle: { _ in }
        )
        _ = controls.projectMeshSection
        controls.beginHandoff()
    }

    func testAuthorizedHandoffForwardsExactTaskAndProjectScopes() async throws {
        let model = AppModel()
        let sourcePairing = try securePairing(room: "source", device: "MacBook")
        let targetPairing = try securePairing(room: "target", device: "Workstation")
        let source = RelayClient(pairing: sourcePairing)
        let target = RelayClient(pairing: targetPairing)
        model.connectionRegistry = ConnectionRegistry(connections: [
            linked(sourcePairing, machine: "MacBook"),
            linked(targetPairing, machine: "Workstation"),
        ], preferredId: sourcePairing.room)
        model.relaysByRoom = [sourcePairing.room: source, targetPairing.room: target]
        model.sessionSourceRooms["claude"] = [sourcePairing.room]
        model.sessionSourceRooms["codex"] = [targetPairing.room]
        var state = snapshot(generatedAt: now)
        let request = event(
            id: "handoff-authorized", type: "HANDOFF_REQUEST",
            payload: .init(capsule: capsule(targetComputer: "Workstation"))
        )
        state.events = [request]
        model.meshSnapshots = ["project": state]
        model.pendingMeshEvents = [request]
        model.meshEventSourceRooms[request.eventId] = sourcePairing.room
        let taskKey = Data(repeating: 3, count: 32).base64EncodedString()
        let projectKey = Data(repeating: 4, count: 32).base64EncodedString()
        XCTAssertTrue(source.installForwardedScopeKey(taskKey, scopeId: "task"))
        XCTAssertTrue(source.installForwardedScopeKey(projectKey, scopeId: "project"))

        model.authorizeMeshEvent(request.eventId)
        XCTAssertTrue(model.pendingMeshEvents.isEmpty)
        XCTAssertEqual(target.sessionKey(for: "task"), taskKey)
        XCTAssertEqual(target.sessionKey(for: "project"), projectKey)

        model.receive(event(
            id: "technical-forward", type: "AGENT_QUESTION", targetSessionId: "codex",
            payload: .init(question: "Field name?", category: "technical")
        ), fromRoom: sourcePairing.room)
        model.meshProjectSourceRooms["project"] = [sourcePairing.room, targetPairing.room]
        model.receive(state, fromRoom: sourcePairing.room)

        model.prepareTaskHandoff(
            session: session(), targetProvider: "codex", targetComputer: "Workstation"
        )
        await Task.yield()
        XCTAssertNil(model.authorizedHandoffRoutes["task"])

        let sheet = TaskHandoffSheet(session: session(), model: model)
        // This computer is a destination too — for another agent — and reads
        // first; the other computer is still where a move goes by default.
        XCTAssertEqual(sheet.targets.map(\.id), [sourcePairing.room, targetPairing.room])
        XCTAssertEqual(sheet.computerName(sheet.targets[1]), "Workstation")
        XCTAssertEqual(sheet.defaultSelection.room, targetPairing.room)
        XCTAssertEqual(sheet.defaultSelection.provider, "codex")
        XCTAssertTrue(sheet.performHandoff(
            targetRoom: targetPairing.room, targetProvider: "codex"
        ))
        XCTAssertFalse(sheet.performHandoff(targetRoom: "missing", targetProvider: "codex"))
    }

    func testValidReceiptUpdatesOwnerWhileForgedReceiptIsIgnored() throws {
        let model = AppModel()
        let request = event(
            id: "request", type: "HANDOFF_REQUEST",
            payload: .init(capsule: capsule(targetComputer: "Workstation"))
        )
        var state = snapshot(generatedAt: now)
        state.events = [request]
        model.meshSnapshots = ["project": state]
        let hash = try XCTUnwrap(ProjectMeshReceiptValidator.capsuleHash(request.payload.capsule!))
        let receipt = ProjectHandoffReceipt(
            sourceSessionId: "claude", targetSessionId: "codex", taskId: "task",
            capsuleHash: hash, acceptedAt: now + 1
        )
        let accepted = event(
            id: "accepted", type: "HANDOFF_ACCEPTED", targetSessionId: "claude",
            payload: .init(receipt: receipt), sourceSessionId: "codex"
        )
        model.receive(accepted, fromRoom: "target")
        XCTAssertEqual(model.meshSnapshots["project"]?.tasks[0].ownerSessionId, "codex")

        let forgedReceipt = ProjectHandoffReceipt(
            sourceSessionId: "claude", targetSessionId: "attacker", taskId: "task",
            capsuleHash: String(repeating: "0", count: 64), acceptedAt: now + 2
        )
        model.receive(event(
            id: "forged", type: "HANDOFF_ACCEPTED", payload: .init(receipt: forgedReceipt),
            sourceSessionId: "attacker"
        ), fromRoom: "target")
        XCTAssertFalse(model.meshEvents(forTaskId: "task").contains { $0.eventId == "forged" })
    }

    func renderMeshChat<Content: View>(_ view: Content) {
        let frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        let host = UIHostingController(rootView: NavigationView { view })
        let window = UIWindow(frame: frame)
        window.rootViewController = host
        window.isHidden = false
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertNotNil(host.view.window)
        window.isHidden = true
        window.rootViewController = nil
    }
}
