import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testFreshIdleObservationReleasesOneFollowUpForItsOwnRoom() throws {
        let model = AppModel()
        model.deliveries = []
        model.activities = [:]
        model.localOnlySessionIds = []
        model.connectionRegistry = testConnectionRegistry()
        model.sessionSourceRooms = ["session-a": ["room-a"]]
        model.roomRuntime["room-a"] = AppModel.RoomRuntime(socketUp: true)
        model.relaysByRoom["room-a"] = RelayClient(pairing: testPairing())
        model.demoMode = true
        let session = SessionInfo(sessionId: "session-a", agent: "codex", state: "idle",
            startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        model.queueChatMessage("First", to: session)
        model.queueChatMessage("Second", to: session)
        let rows = model.chatQueuedMessages(for: session)
        model.resumeChatQueues(observed: [session], fromRoom: "room-b")
        XCTAssertEqual(model.chatQueuedMessages(for: session).count, 2)
        model.resumeChatQueues(observed: [session], fromRoom: "room-a")
        XCTAssertEqual(model.activities[session.sessionId]?.entries.map(\.id), ["local-user-\(rows[0].id)"])
        XCTAssertEqual(model.chatQueuedMessages(for: session).map(\.text), ["Second"])
        model.resumeChatQueues(observed: [session], localOnly: true)
        XCTAssertEqual(model.chatQueuedMessages(for: session).count, 1)
    }

    @MainActor
    func testSendNowWithoutAComputerShowsFailureAndRetryKeepsOneBubble() throws {
        let model = AppModel()
        model.deliveries = []
        model.activities = [:]
        model.connectionRegistry = .empty
        model.localOnlySessionIds = []
        model.sessionSourceRooms = [:]
        let session = SessionInfo(sessionId: "unrouted", agent: "codex", state: "working",
            startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        model.queueChatMessage("Next", to: session)
        let id = try XCTUnwrap(model.deliveries.first?.id)
        model.sendChatQueuedMessageNow(id)
        XCTAssertEqual(model.deliveries.first?.state, .failed)
        XCTAssertEqual(model.deliveries.first?.chatQueue?.waiting, false)
        model.retryDelivery(id)
        XCTAssertEqual(model.activities[session.sessionId]?.entries.count, 1)
        XCTAssertEqual(model.deliveries.first?.id, id)
        XCTAssertTrue(model.cancelChatQueuedMessage(id))
    }

    #if targetEnvironment(macCatalyst)
    @MainActor
    func testLocalCatalogReconcilesAnInterruptedQueuedSendAfterRestart() throws {
        let model = AppModel()
        model.deliveries = []
        let session = SessionInfo(sessionId: "local-restarted", agent: "codex", state: "idle",
            startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        model.queueChatMessage("Next", to: session)
        model.deliveries[0].chatQueue = ChatMessageQueueContext(waiting: false, transport: .localMCP,
                                                             taskId: "task")
        model.deliveries[0].state = .sending
        model.deliveries[0].attempts = 1
        model.deliveries[0].attemptGeneration = "persisted"
        model.resumeChatQueues(observed: [session], localOnly: true)
        XCTAssertEqual(model.deliveries[0].state, .failed)
        XCTAssertEqual(model.deliveries[0].attempts, 1)
        XCTAssertTrue(ChatMessageQueuePolicy.canCancel(model.deliveries[0]))
    }

    @MainActor
    func testInterruptedLocalQueueRequiresInspectionAndLateCompletionCannotOverwriteRetry() throws {
        let model = AppModel()
        model.deliveries = []
        let session = SessionInfo(sessionId: "local-queue", agent: "codex", state: "idle",
            startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        model.queueChatMessage("Next", to: session)
        model.deliveries[0].chatQueue = ChatMessageQueueContext(waiting: false, transport: .localMCP,
                                                             taskId: "task")
        let id = model.deliveries[0].id
        model.attemptDelivery(id)
        XCTAssertEqual(model.deliveries[0].attempts, 0)
        model.deliveries[0].state = .sending
        model.deliveries[0].attempts = 1
        model.deliveries[0].attemptGeneration = "old"
        model.liveDeliveryAttemptGenerations.insert("old")
        model.attemptDelivery(id)
        XCTAssertEqual(model.deliveries[0].state, .sending)
        model.liveDeliveryAttemptGenerations.remove("old")
        model.retryQueuedDeliveries()
        XCTAssertEqual(model.deliveries[0].state, .failed)
        XCTAssertNotNil(model.deliveries[0].error)
        model.deliveries[0].attemptGeneration = "new"
        model.completeLocalChatQueue(id, generation: "old", accepted: true, error: nil)
        XCTAssertEqual(model.deliveries[0].state, .failed)
        model.completeLocalChatQueue(id, generation: "new", accepted: false, error: nil)
        XCTAssertNotNil(model.deliveries[0].error)
        model.deliveries[0].attemptGeneration = "completed"
        model.completeLocalChatQueue(id, generation: "completed", accepted: true, error: nil)
        XCTAssertEqual(model.deliveries[0].state, .delivered)
    }
    #endif
}
