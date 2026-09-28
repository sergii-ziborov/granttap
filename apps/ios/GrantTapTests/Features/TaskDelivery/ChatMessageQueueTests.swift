import XCTest
@testable import GrantTap

@MainActor
final class ChatMessageQueueTests: XCTestCase {
    private func makeModel() -> AppModel {
        let model = AppModel()
        model.deliveries = []
        model.activities = [:]
        model.sessions = []
        model.sessionSourceRooms = [:]
        model.sessionIdAliases = [:]
        model.localOnlySessionIds = []
        model.connectionRegistry = .empty
        return model
    }

    private func session(_ state: String = "working", agent: String = "codex") -> SessionInfo {
        SessionInfo(sessionId: "queue-test", agent: agent, state: state,
                    startedAt: 1, lastActivityAt: 1, tokensSession: 0, tokensLastTurn: 0)
    }

    func testQueuedMessageStaysOutsideTranscriptUntilReleased() {
        let model = makeModel()
        let session = session()
        model.sessions = [session]

        XCTAssertTrue(model.queueChatMessage("Next step", to: session))

        XCTAssertEqual(model.deliveries.count, 1)
        XCTAssertEqual(model.deliveries.first?.attempts, 0)
        XCTAssertTrue((model.activities[session.sessionId]?.entries ?? []).isEmpty)
        model.retryQueuedDeliveries()
        model.resumeChatQueues(observed: [self.session("idle")])
        XCTAssertEqual(model.deliveries.first?.attempts, 0)
        XCTAssertEqual(model.deliveries.first?.chatQueue?.waiting, true)
    }

    func testPersistenceRetainsAttachmentBytesAndQueueAfterRestart() throws {
        let model = makeModel()
        let attachment = UserAttachment(name: "file.txt", mimeType: "text/plain",
                                        data: Data("Exact bytes\n".utf8).base64EncodedString())
        XCTAssertTrue(model.queueChatMessage("Next", to: session(), attachments: [attachment]))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("outbox.json")
        DeliveryPersistence.save(model.deliveries, to: url)
        let restored = makeModel()
        restored.deliveries = DeliveryPersistence.load(from: url)
        XCTAssertEqual(restored.chatQueuedMessages(for: session()).count, 1)
        XCTAssertEqual(restored.deliveries.first?.attachments.first?.data, attachment.data)
        XCTAssertEqual(restored.deliveries.first?.id, model.deliveries.first?.id)
        XCTAssertEqual(restored.deliveries.first?.chatQueue?.waiting, true)
    }

    func testCancelRemovesOnlyChosenRowAndNeverCreatesTranscriptEntry() throws {
        let model = makeModel()
        model.queueChatMessage("First", to: session())
        model.queueChatMessage("Second", to: session())
        let first = try XCTUnwrap(model.chatQueuedMessages(for: session()).first)
        XCTAssertTrue(model.cancelChatQueuedMessage(first.id))
        XCTAssertEqual(model.chatQueuedMessages(for: session()).map(\.text), ["Second"])
        XCTAssertTrue(model.activities.isEmpty)
        XCTAssertFalse(model.cancelChatQueuedMessage(first.id))
    }

    func testSendNowReleasesExactIDOnceWhileKeepingLaterQueueHeld() throws {
        let model = makeModel()
        model.queueChatMessage("First", to: session())
        model.queueChatMessage("Second", to: session())
        let rows = model.chatQueuedMessages(for: session())
        let first = try XCTUnwrap(rows.first)
        model.demoMode = true
        model.sendChatQueuedMessageNow(first.id)
        model.sendChatQueuedMessageNow(first.id)
        XCTAssertEqual(model.activities[first.sessionId!]?.entries.map(\.id), ["local-user-\(first.id)"])
        XCTAssertEqual(model.chatQueuedMessages(for: session()).map(\.text), ["Second"])
        XCTAssertEqual(model.deliveries.first { $0.id == first.id }?.state, .delivered)
    }

    func testQueueCannotCancelOrResendAnAlreadySubmittedMessage() throws {
        let model = makeModel()
        model.queueChatMessage("Submitted", to: session())
        let id = try XCTUnwrap(model.deliveries.first?.id)
        model.deliveries[0].state = .sending
        model.deliveries[0].attempts = 1
        model.deliveries[0].chatQueue?.waiting = false
        XCTAssertFalse(model.cancelChatQueuedMessage(id))
        model.sendChatQueuedMessageNow(id)
        XCTAssertEqual(model.deliveries.first?.attempts, 1)
        XCTAssertTrue(model.activities.isEmpty)
    }

    func testWaitingRowsSurviveLongOfflinePeriodAndRepeatedTextEcho() throws {
        let model = makeModel()
        model.queueChatMessage("Again", to: session())
        let row = try XCTUnwrap(model.deliveries.first)
        model.deliveries[0] = OutgoingDelivery(
            id: row.id, text: row.text, agent: row.agent, cwd: nil, sessionId: row.sessionId,
            requestId: nil, attachments: [], preferredMcp: nil, skill: nil,
            createdAt: 1, updatedAt: 1, attempts: 0, state: .queued, error: nil,
            nextRetryAt: nil, chatQueue: row.chatQueue)
        model.pruneStaleDeliveries()
        model.applyActivity(SessionActivity(sessionId: "queue-test", agent: "codex", state: "working",
            entries: [ActivityEntry(id: "older-native-user", kind: "user", text: "Again", createdAt: 2)],
            generatedAt: 3))
        XCTAssertEqual(model.deliveries.map(\.id), [row.id])
        XCTAssertEqual(model.orphanDeliveries(for: "queue-test").count, 0)
    }

    func testQueueAdmissionRejectsEmptyAndOversizedText() {
        let model = makeModel()
        XCTAssertFalse(model.queueChatMessage(" \n", to: session()))
        XCTAssertFalse(model.queueChatMessage(String(repeating: "x", count: 8_001), to: session()))
        XCTAssertTrue(model.deliveries.isEmpty)
    }

    func testFullQueueRetainsAllEarlierMessages() {
        let model = makeModel()
        for index in 0..<32 { XCTAssertTrue(model.queueChatMessage("Item \(index)", to: session())) }
        let original = Set(model.deliveries.map(\.id))
        XCTAssertFalse(model.queueChatMessage("Over capacity", to: session()))
        XCTAssertEqual(model.chatQueuedMessages(for: session()).count, 32)
        XCTAssertTrue(original.isSubset(of: Set(model.deliveries.map(\.id))))
    }

    func testNativeRemapPreservesQueueAndChosenOptions() throws {
        let model = makeModel()
        model.localOnlySessionIds = ["queue-test"]
        model.queueChatMessage("After startup", to: session())
        model.deliveries[0].model = "chosen-model"
        let context = model.deliveries[0].chatQueue
        model.remapLocalSession(from: "queue-test", to: "native-test")
        XCTAssertEqual(model.deliveries.first?.sessionId, "native-test")
        XCTAssertEqual(model.deliveries.first?.chatQueue, context)
        XCTAssertEqual(model.deliveries.first?.model, "chosen-model")
        XCTAssertEqual(model.deliveries.first?.awaitingSessionRemap, false)
        XCTAssertTrue(model.activities.isEmpty)
    }

    func testNoQueueRowsInAnotherProviderOrRoom() {
        let model = makeModel()
        model.queueChatMessage("Scoped", to: session())
        let other = session(agent: "claude")
        XCTAssertTrue(model.chatQueuedMessages(for: other).isEmpty)
        model.deliveries[0].roomId = "another-room"
        XCTAssertTrue(model.chatQueuedMessages(for: session()).isEmpty)
    }

    func testACompletedQueuedFileKeepsItsPreviewBytes() throws {
        let model = makeModel()
        model.demoMode = true
        let attachment = UserAttachment(name: "file.swift", mimeType: "text/plain",
                                        data: Data("let value = 1\n".utf8).base64EncodedString())
        model.queueChatMessage("File", to: session(), attachments: [attachment])
        let id = try XCTUnwrap(model.deliveries.first?.id)
        model.sendChatQueuedMessageNow(id)
        model.pruneStaleDeliveries()
        XCTAssertEqual(model.sentAttachment(forEntryId: "local-user-\(id)", name: "file.swift")?.data,
                       Data("let value = 1\n".utf8))
    }

    func testNormalSendWhileWorkingQueuesWithoutSendingOrAppendingToTranscript() {
        let model = makeModel()
        let session = session()
        model.sessions = [session]
        TaskChatView(session: session, modelOverride: model, initialDraft: "Continue later").send()
        XCTAssertEqual(model.chatQueuedMessages(for: session).map(\.text), ["Continue later"])
        XCTAssertEqual(model.deliveries.first?.chatQueue?.waiting, true)
        XCTAssertEqual(model.deliveries.first?.attempts, 0)
        XCTAssertTrue(model.activities.isEmpty)
    }

    func testPausedChatCanQueueButSendNowStaysBlocked() {
        let model = makeModel()
        var session = session("idle")
        session.paused = true
        model.sessions = [session]
        TaskChatView(session: session, modelOverride: model, initialDraft: "Send now").sendImmediately()
        XCTAssertTrue(model.deliveries.isEmpty)
        TaskChatView(session: session, modelOverride: model, initialDraft: "After resuming").send()
        XCTAssertEqual(model.chatQueuedMessages(for: session).map(\.text), ["After resuming"])
        XCTAssertEqual(model.deliveries.first?.chatQueue?.waiting, true)
        XCTAssertTrue(model.activities.isEmpty)
    }

    func testDelayedQueueStartsDeliveryLifetimeWhenSentAndKeepsItsOriginalOrder() {
        let model = makeModel()
        model.demoMode = true
        let attachment = UserAttachment(name: "kept.swift", mimeType: "text/plain",
                                        data: Data("let kept = true\n".utf8).base64EncodedString())
        model.deliveries = [1, 2].map { index in
            OutgoingDelivery(id: "delayed-\(index)", text: "Next", agent: "codex", cwd: nil,
                sessionId: "queue-test", requestId: nil, attachments: index == 1 ? [attachment] : [],
                preferredMcp: nil, skill: nil, createdAt: Double(index), updatedAt: Double(index),
                attempts: 0, state: .queued, error: nil, nextRetryAt: nil,
                chatQueue: ChatMessageQueueContext(waiting: true, transport: .relay, taskId: nil))
        }
        let before = Date().timeIntervalSince1970 * 1_000
        model.sendChatQueuedMessageNow("delayed-1")
        XCTAssertGreaterThanOrEqual(model.deliveries[0].createdAt, before)
        model.pruneStaleDeliveries()
        XCTAssertEqual(model.sentAttachment(forEntryId: "local-user-delayed-1", name: "kept.swift")?.data,
                       Data("let kept = true\n".utf8))
        XCTAssertEqual(TaskDeliveryQueue.oldestFirst(model.deliveries).map(\.id),
                       ["delayed-1", "delayed-2"])
        XCTAssertEqual(model.chatQueuedMessages(for: session()).map(\.id), ["delayed-2"])
    }
}
