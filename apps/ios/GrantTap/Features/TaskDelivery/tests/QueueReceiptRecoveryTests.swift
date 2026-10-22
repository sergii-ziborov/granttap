import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testReceiptArchivesLegacyPicturesBeforeRetiringARowWhoseLocalBubbleIsMissing() {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        model.demoMode = true
        model.connectionRegistry = testConnectionRegistry()
        model.sessionSourceRooms = ["existing-session": ["room-a"]]
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==")!
        defer { ReplicaImageStore.shared.clear() }
        var row = existingSessionDelivery(createdAt: now - 1_000, id: "legacy-picture", agent: "codex")
        row.chatQueue = .init(waiting: false, transport: .relay, taskId: nil)
        row.attachments = [.init(name: "photo.png", mimeType: "image/png", data: png.base64EncodedString())]
        model.deliveries = [row]
        model.activities = [:]
        let snapshot = SessionActivity(sessionId: row.sessionId!, agent: "codex", state: "working", entries: [
            .init(id: "native-caption", kind: "user", text: row.text, createdAt: now),
            .init(id: "native-picture", kind: "user", text: "", createdAt: now, attachments: ["Image"]),
        ], generatedAt: now)
        model.confirmDeliveriesFromNativeTranscript(snapshot, sourceRoom: "room-a")
        XCTAssertEqual(model.deliveries.first?.state, .delivered)
        model.deliveries = []
        XCTAssertEqual(model.cachedMessageImage(sessionId: row.sessionId!, imageId: "native-picture"), png)
    }

    @MainActor
    func testConfirmedRefusalCannotBeOverriddenByAnotherNativeMessageWithTheSameText() {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        model.demoMode = true
        var row = existingSessionDelivery(createdAt: now - 1_000, id: "refused", agent: "codex")
        row.state = .failed
        row.rejectedByComputer = true
        row.chatQueue = .init(waiting: false, transport: .relay, taskId: nil)
        model.deliveries = [row]
        let local = ActivityEntry(id: "local-user-refused", kind: "user", text: row.text, createdAt: now - 1_000)
        let existing = SessionActivity(sessionId: row.sessionId!, agent: "codex", state: "idle",
                                        entries: [local], generatedAt: now)
        let native = SessionActivity(sessionId: row.sessionId!, agent: "codex", state: "working",
            entries: [.init(id: "other-native", kind: "user", text: row.text, createdAt: now)], generatedAt: now)
        model.confirmDeliveriesFromNativeTranscript(native, sourceRoom: "room-a")
        XCTAssertEqual(model.deliveries.first?.state, .failed)
        XCTAssertEqual(model.reconcileOptimisticUserBubbles(existing: existing, incoming: native,
            sourceNamespace: "room-a").entries.map(\.id), [local.id])
    }

    @MainActor
    func testOnePictureGroupCannotConfirmTwoQueuedMessagesEvenAfterRestart() throws {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        model.demoMode = true
        model.deliveries = ["first-photos", "second-photos"].map { id in
            var row = existingSessionDelivery(createdAt: now - 1_000, id: id, text: "", agent: "codex")
            row.chatQueue = .init(waiting: false, transport: .relay, taskId: nil)
            row.attachments = ["one.jpg", "two.jpg"].map { .init(name: $0, mimeType: "image/jpeg", data: "aA==") }
            return row
        }
        let activity = SessionActivity(sessionId: "existing-session", agent: "codex", state: "working",
            entries: ["photo-one", "photo-two"].map {
                .init(id: $0, kind: "user", text: "", createdAt: now, attachments: ["Image"])
            }, generatedAt: now)
        model.confirmDeliveriesFromNativeTranscript(activity, sourceRoom: "room-a")
        XCTAssertEqual(model.deliveries.filter { $0.state == .delivered }.count, 1)
        model.deliveries = try JSONDecoder().decode([OutgoingDelivery].self,
            from: JSONEncoder().encode(model.deliveries))
        model.confirmDeliveriesFromNativeTranscript(activity, sourceRoom: "room-a")
        XCTAssertEqual(model.deliveries.filter { $0.state == .delivered }.count, 1)
    }

    @MainActor
    func testIdleTranscriptReconcilesPreviousReceiptAndAutomaticallyDispatchesNextMessage() throws {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        model.demoMode = true
        model.localOnlySessionIds = []
        model.connectionRegistry = testConnectionRegistry()
        model.sessionSourceRooms = ["session-a": ["room-a"]]
        model.roomRuntime["room-a"] = AppModel.RoomRuntime(socketUp: true)
        model.relaysByRoom["room-a"] = RelayClient(pairing: testPairing())
        let session = SessionInfo(sessionId: "session-a", agent: "codex", state: "working",
            startedAt: now - 10_000, lastActivityAt: now, tokensSession: 0, tokensLastTurn: 0)
        model.sessions = [session]
        var sent = existingSessionDelivery(createdAt: now - 2_000, id: "old-sent",
            text: "Previous request", sessionId: session.sessionId, agent: "codex")
        sent.chatQueue = .init(waiting: false, transport: .relay, taskId: nil)
        sent.processingAcknowledgedAt = now - 1_000
        model.deliveries = [sent]
        model.queueChatMessage("Next request", to: session)
        model.applyActivity(.init(sessionId: session.sessionId, agent: "codex", state: "idle",
            entries: [.init(id: "native-previous", kind: "user", text: sent.text, createdAt: now)],
            generatedAt: now), sourceNamespace: "room-a")
        XCTAssertTrue(model.chatQueuedMessages(for: session).isEmpty)
        XCTAssertTrue(model.deliveries.allSatisfy { $0.state == .delivered })
        XCTAssertEqual(model.activities[session.sessionId]?.entries.filter {
            $0.id.hasPrefix("local-user-") && $0.text == "Next request"
        }.count, 1)
    }

    @MainActor
    func testCheckingLegacyQueueUsesAlreadySavedNativeReceiptWithoutTransport() throws {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        model.demoMode = true
        var row = existingSessionDelivery(createdAt: now - 2_000, id: "saved-queue", agent: "codex")
        row.chatQueue = .init(waiting: false, transport: .relay, taskId: nil)
        row.processingAcknowledgedAt = now - 1_000
        model.deliveries = [row]
        model.connectionRegistry = testConnectionRegistry()
        model.sessionSourceRooms = [row.sessionId!: ["room-a"]]
        model.activities = [row.sessionId!: .init(sessionId: row.sessionId!, agent: "codex", state: "idle",
            entries: [.init(id: "saved-native", kind: "user", text: row.text, createdAt: now)], generatedAt: now)]
        model.checkLegacyQueuedDelivery(at: 0)
        XCTAssertEqual(model.deliveries.first?.state, .delivered)
        XCTAssertEqual(model.deliveries.first?.nativeEchoId, "saved-native")
        let reopened = try JSONDecoder().decode([OutgoingDelivery].self,
            from: JSONEncoder().encode(model.deliveries))
        XCTAssertEqual(reopened.first?.state, .delivered)
    }

    @MainActor
    func testPictureOnlyNativeReceiptRetiresReleasedQueueButNotAnotherConversation() {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        model.demoMode = true
        var row = existingSessionDelivery(createdAt: now - 2_000, id: "picture-queue", text: "", agent: "codex")
        row.chatQueue = .init(waiting: false, transport: .relay, taskId: nil)
        row.attachments = [.init(name: "photo.jpg", mimeType: "image/jpeg", data: "aA==")]
        row.processingAcknowledgedAt = now - 1_000
        model.deliveries = [row]
        let entry = ActivityEntry(id: "native-picture", kind: "user", text: "", createdAt: now,
                                  attachments: ["Image"])
        let activity = SessionActivity(sessionId: row.sessionId!, agent: "codex", state: "working",
                                        entries: [entry], generatedAt: now)
        model.confirmDeliveriesFromNativeTranscript(activity, sourceRoom: "other-room")
        XCTAssertEqual(model.deliveries.first?.state, .sending)
        model.confirmDeliveriesFromNativeTranscript(activity, sourceRoom: "room-a")
        XCTAssertEqual(model.deliveries.first?.state, .delivered)
        XCTAssertEqual(model.deliveries.first?.nativeEchoId, entry.id)
    }
}
