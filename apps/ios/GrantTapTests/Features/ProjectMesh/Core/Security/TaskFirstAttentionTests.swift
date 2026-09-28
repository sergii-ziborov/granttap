import XCTest
@testable import GrantTap

@MainActor
extension ProjectMeshRuntimeTests {
    func testTaskCatalogKeepsSyntheticOwnerAndNeverRoutesToOldNativeSession() {
        let model = AppModel()
        var state = snapshot(generatedAt: now)
        state.executions.append(.init(
            taskId: "task", sessionId: "grok-bot:qa:42", provider: "grok_bot",
            actorId: "qa", computerId: "grok-cloud", workspace: "/repo",
            startedAt: now + 1
        ))
        state.tasks[0].ownerSessionId = "grok-bot:qa:42"
        model.meshSnapshots = ["project": state]
        model.sessions = [session()]

        let items = TaskListCatalog.items(model: model, sessions: model.sessions)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].ownerExecution?.sessionId, "grok-bot:qa:42")
        XCTAssertNil(items[0].currentSession)
        XCTAssertEqual(items[0].destination, .task(.init(projectId: "project", taskId: "task")))

        XCTAssertNotEqual(items[0].destination, .session("claude"))
    }

    func testTaskCatalogIncludesMeshTaskWithoutAnyNativeSession() {
        let model = AppModel()
        model.meshSnapshots = ["project": snapshot(generatedAt: now)]
        model.sessions = []

        let item = TaskListCatalog.items(model: model, sessions: []).first
        XCTAssertEqual(item?.title, "Pairing")
        XCTAssertEqual(item?.ownerExecution?.sessionId, "claude")
        XCTAssertNil(item?.currentSession)
    }

    func testTaskCatalogPrefersCurrentNativeConversationTitle() {
        let model = AppModel()
        model.meshSnapshots = ["project": snapshot(generatedAt: now)]
        var native = session()
        native.title = "Current native conversation"
        model.sessions = [native]

        let item = TaskListCatalog.items(model: model, sessions: model.sessions).first

        XCTAssertEqual(item?.title, "Current native conversation")
        XCTAssertEqual(item?.currentSession?.sessionId, native.sessionId)
    }

    func testTaskCatalogTieBreaksAndKeepsNewestLegacyExecution() {
        let model = AppModel()
        model.meshSnapshots = [:]
        let alpha = legacySession(id: "alpha", projectId: nil, taskId: nil, at: 10)
        let beta = legacySession(id: "beta", projectId: nil, taskId: nil, at: 10)
        let newest = legacySession(id: "new", projectId: "legacy", taskId: "task", at: 20)
        let older = legacySession(id: "old", projectId: "legacy", taskId: "task", at: 5)

        let items = TaskListCatalog.items(
            model: model, sessions: [newest, older, beta, alpha]
        )

        XCTAssertEqual(items.map(\.id), ["session:new", "session:alpha", "session:beta"])
    }

    func testPendingAttentionPersistsAuthenticatedRouteAndSnoozeState() throws {
        let legacyState = try JSONDecoder().decode(
            ProjectMeshAttentionState.self,
            from: Data(#"{"status":"pending"}"#.utf8)
        )
        XCTAssertNil(legacyState.updatedAt)
        let question = event(
            id: "durable-question", type: "AGENT_QUESTION",
            payload: .init(question: "Ship?", category: "product")
        )
        let state = ProjectMeshAttentionState(status: .snoozed, snoozedUntil: now + 60_000)
        let archive = ProjectMeshArchive(
            snapshots: ["project": snapshot(generatedAt: now)], pendingEvents: [question],
            eventSourceRooms: [question.eventId: "grok-room"],
            attentionStates: [question.eventId: state]
        )
        ProjectMeshPersistence.save(archive)

        let restored = ProjectMeshPersistence.load()
        XCTAssertEqual(restored.eventSourceRooms[question.eventId], "grok-room")
        XCTAssertEqual(restored.attentionStates[question.eventId], state)
        XCTAssertEqual(restored.pendingEvents, [question])
    }

    func testSecondaryAttentionActionsDoNotDeleteUnansweredQuestions() {
        let model = AppModel()
        model.agentMeshPreferences = .defaults
        let question = event(
            id: "snooze", type: "AGENT_QUESTION",
            payload: .init(question: "Ship?", category: "product")
        )
        model.pendingMeshEvents = [question]
        model.meshAttentionStates[question.eventId] = .init(status: .pending)

        model.performMeshSecondaryAction(question.eventId)

        XCTAssertEqual(model.pendingMeshEvents, [question])
        XCTAssertTrue(model.meshNeedsYouEvents.isEmpty)
        XCTAssertEqual(model.meshAttentionStates[question.eventId]?.status, .snoozed)
    }

    func testAttentionReceiptHistoryIsBoundedAndDropsOrphanedPendingState() {
        let model = AppModel()
        model.pendingMeshEvents = []
        model.meshAttentionStates = Dictionary(uniqueKeysWithValues: (0..<300).map { index in
            let updatedAt = index < 2 ? 1_000 : Double(index)
            return ("receipt-\(index)", ProjectMeshAttentionState(
                status: .answered, createdAt: Double(index),
                presentedAt: Double(index), updatedAt: updatedAt
            ))
        })
        model.meshAttentionStates["orphan-pending"] = .init(status: .pending)

        model.persistMeshState()

        XCTAssertEqual(model.meshAttentionStates.count, 256)
        XCTAssertNil(model.meshAttentionStates["orphan-pending"])
        XCTAssertTrue(model.meshAttentionStates.values.allSatisfy { $0.status == .answered })
    }

    func testDeclineWithoutAuthenticatedRouteKeepsHandoffPending() {
        let model = AppModel()
        model.agentMeshPreferences = .defaults
        let request = event(
            id: "unroutable", type: "HANDOFF_REQUEST",
            payload: .init(capsule: capsule(targetComputer: "Workstation"))
        )
        model.pendingMeshEvents = [request]
        model.meshAttentionStates[request.eventId] = .init(status: .pending)

        model.performMeshSecondaryAction(request.eventId)

        XCTAssertEqual(model.pendingMeshEvents, [request])
        XCTAssertEqual(model.meshAttentionStates[request.eventId]?.status, .pending)
        XCTAssertTrue(model.log.last?.contains("handoff decline unavailable") == true)
    }

    func testRestoredQuestionUsesItsPersistedAuthenticatedRoom() throws {
        let model = AppModel()
        model.agentMeshPreferences = .defaults
        model.meshSnapshots = ["project": snapshot(generatedAt: now)]
        let question = event(
            id: "restored", type: "AGENT_QUESTION",
            payload: .init(question: "Ship?", category: "product")
        )
        let pairing = try securePairing(room: "restored-room", device: "Grok Bot")
        let relay = RelayClient(pairing: pairing)
        model.relaysByRoom[pairing.room] = relay
        XCTAssertTrue(relay.installForwardedScopeKey(
            Data(repeating: 8, count: 32).base64EncodedString(), scopeId: "task"
        ))
        model.pendingMeshEvents = [question]
        model.meshEventSourceRooms = [question.eventId: pairing.room]

        model.answerMeshQuestion(question.eventId, text: "Ship it")

        XCTAssertTrue(model.pendingMeshEvents.isEmpty)
        XCTAssertEqual(
            model.meshEvents(forTaskId: "task").last?.payload.answer, "Ship it"
        )
        XCTAssertEqual(model.meshAttentionStates[question.eventId]?.status, .answered)
        XCTAssertEqual(
            ProjectMeshPersistence.load().attentionStates[question.eventId]?.status,
            .answered
        )
        relay.disconnect()
    }

    func testDecliningHandoffPublishesARejectionInsteadOfDroppingIt() throws {
        let model = AppModel()
        model.agentMeshPreferences = .defaults
        model.meshSnapshots = ["project": snapshot(generatedAt: now)]
        let request = event(
            id: "decline", type: "HANDOFF_REQUEST",
            payload: .init(capsule: capsule(targetComputer: "Workstation"))
        )
        let pairing = try securePairing(room: "decline-room", device: "MacBook")
        let relay = RelayClient(pairing: pairing)
        model.relaysByRoom[pairing.room] = relay
        XCTAssertTrue(relay.installForwardedScopeKey(
            Data(repeating: 9, count: 32).base64EncodedString(), scopeId: "task"
        ))
        model.pendingMeshEvents = [request]
        model.meshEventSourceRooms = [request.eventId: pairing.room]

        model.performMeshSecondaryAction(request.eventId)

        XCTAssertTrue(model.pendingMeshEvents.isEmpty)
        XCTAssertEqual(model.meshEvents(forTaskId: "task").last?.eventType, "HANDOFF_REJECTED")
        XCTAssertEqual(model.meshAttentionStates[request.eventId]?.status, .declined)
        relay.disconnect()
    }

    private func legacySession(
        id: String, projectId: String?, taskId: String?, at: Double
    ) -> SessionInfo {
        .init(
            sessionId: id, agent: "codex", projectId: projectId, taskId: taskId,
            title: id, state: "idle", startedAt: at, lastActivityAt: at,
            tokensSession: 0, tokensLastTurn: 0
        )
    }
}
