import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testNativeEchoIsScopedAndEachEntryConfirmsOnlyOneOperation() {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        model.demoMode = true
        var first = existingSessionDelivery(createdAt: now - 2_000, id: "one", agent: "codex")
        var second = existingSessionDelivery(createdAt: now - 1_000, id: "two", agent: "codex")
        first.processingAcknowledgedAt = now
        second.processingAcknowledgedAt = now
        model.deliveries = [first, second]
        let echo = ActivityEntry(id: "one-native-input", kind: "user", text: first.text, createdAt: now)
        func snapshot(agent: String = "codex", entries: [ActivityEntry]) -> SessionActivity {
            SessionActivity(sessionId: first.sessionId!, agent: agent, state: "working",
                entries: entries, generatedAt: now)
        }
        model.confirmDeliveriesFromNativeTranscript(snapshot(entries: [echo]), sourceRoom: "other-room")
        model.confirmDeliveriesFromNativeTranscript(snapshot(agent: "claude", entries: [echo]), sourceRoom: "room-a")
        XCTAssertEqual(model.deliveries.filter { $0.state == .sending }.count, 2)
        model.confirmDeliveriesFromNativeTranscript(snapshot(entries: [echo]), sourceRoom: "room-a")
        model.confirmDeliveriesFromNativeTranscript(snapshot(entries: [echo]), sourceRoom: "room-a")
        XCTAssertEqual(model.deliveries.filter { $0.state == .delivered }.count, 1)
        XCTAssertEqual(model.deliveries.filter { $0.state == .sending }.count, 1)
        model.deliveries = (try? JSONDecoder().decode([OutgoingDelivery].self,
            from: JSONEncoder().encode(model.deliveries))) ?? []
        model.confirmDeliveriesFromNativeTranscript(snapshot(entries: [echo]), sourceRoom: "room-a")
        XCTAssertEqual(model.deliveries.filter { $0.state == .sending }.count, 1)
    }

    @MainActor
    func testWaitingQueueAndOldTranscriptCannotConfirmANewRetry() {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        model.demoMode = true
        var row = existingSessionDelivery(createdAt: now - 20_000, id: "not-yet-confirmed", agent: "codex")
        row.chatQueue = ChatMessageQueueContext(waiting: true, transport: .relay, taskId: nil)
        let activity = SessionActivity(sessionId: row.sessionId!, agent: "codex", state: "idle",
            entries: [ActivityEntry(id: "old-native", kind: "user", text: row.text, createdAt: now - 10_000)],
            generatedAt: now)
        model.deliveries = [row]
        model.confirmDeliveriesFromNativeTranscript(activity, sourceRoom: "room-a")
        XCTAssertEqual(model.deliveries.first?.state, .sending)
        model.deliveries[0].chatQueue?.waiting = false
        model.deliveries[0].manualRetryStartedAt = now
        model.confirmDeliveriesFromNativeTranscript(activity, sourceRoom: "room-a")
        XCTAssertEqual(model.deliveries.first?.state, .sending)
    }

    @MainActor
    func testCancelledFailureStaysGoneAfterPersistenceAndLateReceipts() throws {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        var row = existingSessionDelivery(createdAt: now, id: "cancelled-failure")
        row.state = .failed
        model.deliveries = [row]
        XCTAssertEqual(model.deliveryCancellationId(forEntryId: "local-user-\(row.id)"), row.id)
        XCTAssertTrue(model.cancelDelivery(row.id))
        let restored = try JSONDecoder().decode([OutgoingDelivery].self,
            from: JSONEncoder().encode(model.deliveries))
        XCTAssertTrue(restored.isEmpty)
        model.receive(DeliveryReceipt(type: "delivery.receipt", messageId: row.id,
            sessionId: row.sessionId, status: "rejected", error: "late", receivedAt: now), fromRoom: "room-a")
        model.retryDelivery(row.id)
        XCTAssertTrue(model.deliveries.isEmpty)
        row.state = .sending
        model.deliveries = [row]
        XCTAssertFalse(model.cancelDelivery(row.id), "cancellation must not pretend to stop a running agent")
    }

    @MainActor
    func testNativeUserEchoRetiresReleasedQueueAndLateReceiptsCannotReviveIt() throws {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        model.demoMode = true
        model.connectionRegistry = testConnectionRegistry()
        var row = existingSessionDelivery(createdAt: now - 2_000, id: "echo-queue",
            sessionId: "native-echo-confirmation", agent: "codex")
        row.processingAcknowledgedAt = now - 1_000
        row.chatQueue = ChatMessageQueueContext(waiting: false, transport: .relay, taskId: nil)
        row.attachments = [UserAttachment(name: "kept.txt", mimeType: "text/plain",
            data: Data("kept".utf8).base64EncodedString())]
        model.deliveries = [row]
        model.activities = [:]
        model.appendQueuedMessageToTranscript(row)
        model.applyActivity(SessionActivity(sessionId: row.sessionId!, agent: "codex", state: "working",
            entries: [ActivityEntry(id: "native-echo", kind: "user", text: row.text, createdAt: now)],
            generatedAt: now), sourceNamespace: "room-a")
        let session = SessionInfo(sessionId: row.sessionId!, agent: "codex", state: "working",
            startedAt: now, lastActivityAt: now, tokensSession: 0, tokensLastTurn: 0)
        XCTAssertTrue(model.chatQueuedMessages(for: session).isEmpty)
        XCTAssertEqual(model.deliveries.first?.state, .delivered)
        XCTAssertNil(model.deliveries.first?.processingAcknowledgedAt)
        for status in ["accepted", "rejected"] {
            model.receive(DeliveryReceipt(type: "delivery.receipt", messageId: row.id,
                sessionId: row.sessionId, status: status, error: nil, receivedAt: now), fromRoom: "room-a")
        }
        XCTAssertEqual(model.deliveries.first?.state, .delivered)
        XCTAssertEqual(model.sentAttachment(forEntryId: "local-user-\(row.id)", name: "kept.txt")?.data,
                       Data("kept".utf8))
    }

    @MainActor
    func testCompletedImageCannotBecomeFailedAtAnOldProcessingDeadline() {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        var row = existingSessionDelivery(createdAt: now - 2_000, id: "completed-image")
        row.state = .delivered
        row.attachments = [UserAttachment(name: "photo.jpg", mimeType: "image/jpeg", data: "aA==")]
        row.processingAcknowledgedAt = now - DeliveryOutboxPolicy.terminalLifecycleMs - 1
        model.deliveries = [row]
        model.pruneStaleDeliveries()
        XCTAssertEqual(model.deliveries.first?.state, .delivered)
        XCTAssertTrue(model.deliveries.filter { $0.state == .failed }.isEmpty)
    }

    @MainActor
    func testRefusedLegacyQueueRetryUsesFreshIdentityAndKeepsOneBubble() throws {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        model.demoMode = true
        var row = existingSessionDelivery(createdAt: now, id: "refused-queue", agent: "codex")
        row.state = .failed
        row.rejectedByComputer = true
        row.relayStoredAt = now - 1_000
        row.transportAttemptStartedAt = now - 1_000
        row.chatQueue = ChatMessageQueueContext(waiting: false, transport: .relay, taskId: nil)
        model.deliveries = [row]
        model.activities = [:]
        model.appendQueuedMessageToTranscript(row)
        model.sendChatQueuedMessageNow(row.id)
        let retry = try XCTUnwrap(model.deliveries.first)
        XCTAssertNotEqual(retry.id, row.id)
        XCTAssertNil(retry.relayStoredAt)
        XCTAssertNil(retry.transportAttemptStartedAt)
        XCTAssertNotNil(retry.manualRetryStartedAt)
        XCTAssertEqual(model.activities[row.sessionId!]?.entries.map(\.id), ["local-user-\(retry.id)"])
    }

}
