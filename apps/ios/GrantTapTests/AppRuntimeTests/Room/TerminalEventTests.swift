import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testExpiredProcessingRowBecomesVisibleFailureInsteadOfDisappearing() {
        let now = Date().timeIntervalSince1970 * 1000
        let model = AppModel()
        var row = existingSessionDelivery(createdAt: now - 700_000)
        row.processingAcknowledgedAt = now - 700_000
        row.nextRetryAt = now - 370_000
        model.deliveries = [row]

        model.pruneStaleDeliveries()

        XCTAssertEqual(model.deliveries.map(\.id), ["phone-message-1"])
        XCTAssertEqual(model.deliveries.first?.state, .failed)
        XCTAssertNil(model.deliveries.first?.processingAcknowledgedAt)
        XCTAssertNil(model.deliveries.first?.processingRetryStartedAt)
        XCTAssertNotNil(model.deliveries.first?.error)
        XCTAssertGreaterThanOrEqual(model.deliveries.first?.updatedAt ?? 0, now)
    }

    @MainActor
    func testStatusRemapsNewTaskStubWithoutLosingRecoveryPhase() throws {
        let now = Date().timeIntervalSince1970 * 1000
        let model = AppModel()
        model.localOnlySessionIds = ["phone-stub"]
        model.deliveries = [existingSessionDelivery(
            createdAt: now,
            sessionId: "phone-stub",
            agent: "codex"
        )]
        model.receive(DeliveryReceipt(
            type: "delivery.receipt",
            messageId: "phone-message-1",
            sessionId: nil,
            status: "accepted",
            error: nil,
            receivedAt: now + 10
        ), fromRoom: "room-a")
        let retryAt = try XCTUnwrap(model.deliveries.first?.nextRetryAt)
        let acknowledgedAt = try XCTUnwrap(
            model.deliveries.first?.processingAcknowledgedAt
        )

        model.receive(AgentEvent(
            type: "agent.event",
            text: "Запускаю codex…",
            requestId: nil,
            kind: "status",
            sessionId: "machine-session",
            originMessageId: "phone-message-1",
            createdAt: now + 20
        ))

        XCTAssertEqual(model.deliveries.map(\.id), ["phone-message-1"])
        XCTAssertEqual(model.deliveries.first?.sessionId, "machine-session")
        XCTAssertEqual(model.deliveries.first?.state, .sending)
        XCTAssertEqual(model.deliveries.first?.nextRetryAt, retryAt)
        XCTAssertEqual(model.deliveries.first?.processingAcknowledgedAt, acknowledgedAt)
    }

    @MainActor
    func testAcceptedReceiptStillConsumesCorrelatedMcpReply() {
        let now = Date().timeIntervalSince1970 * 1000
        let model = AppModel()
        model.deliveries = [existingSessionDelivery(
            createdAt: now,
            requestId: "mcp-question-1"
        )]

        model.receive(DeliveryReceipt(
            type: "delivery.receipt",
            messageId: "phone-message-1",
            sessionId: "existing-session",
            status: "accepted",
            error: nil,
            receivedAt: now + 10
        ), fromRoom: "room-a")

        XCTAssertTrue(model.deliveries.isEmpty)
    }

    @MainActor
    func testStatusEventWithOriginDoesNotConsumeExistingSessionDelivery() {
        let now = Date().timeIntervalSince1970 * 1000
        let model = AppModel()
        model.deliveries = [existingSessionDelivery(createdAt: now)]

        model.receive(AgentEvent(
            type: "agent.event",
            text: "Передал агенту, жду ответ…",
            requestId: nil,
            kind: "status",
            sessionId: "existing-session",
            originMessageId: "phone-message-1",
            createdAt: now + 20
        ))

        XCTAssertEqual(model.deliveries.map(\.id), ["phone-message-1"])

        model.receive(AgentEvent(
            type: "agent.event",
            text: "Уточнить детали?",
            requestId: nil,
            kind: "question",
            sessionId: "existing-session",
            originMessageId: "phone-message-1",
            createdAt: now + 21
        ))

        XCTAssertEqual(model.deliveries.map(\.id), ["phone-message-1"])
    }

    @MainActor
    func testTerminalResponseWithOriginConsumesExistingSessionDelivery() {
        let now = Date().timeIntervalSince1970 * 1000
        let model = AppModel()
        model.deliveries = [existingSessionDelivery(createdAt: now)]

        model.receive(AgentEvent(
            type: "agent.event",
            text: "Готово",
            requestId: nil,
            kind: "response",
            sessionId: "existing-session",
            originMessageId: "phone-message-1",
            createdAt: now + 20
        ))

        XCTAssertTrue(model.deliveries.isEmpty)
    }

    @MainActor
    func testTerminalResponseKeepsSentPhotoAvailableForPreview() {
        let now = Date().timeIntervalSince1970 * 1000
        let capture = AppModelDemoFixtures.chatCapture(at: now)
        let model = AppModel()
        model.deliveries = [capture.delivery]

        model.receive(AgentEvent(
            type: "agent.event",
            text: "Готово",
            requestId: nil,
            kind: "response",
            sessionId: AppModelDemoFixtures.codexSessionId,
            originMessageId: capture.delivery.id,
            createdAt: now + 20
        ))
        model.pruneStaleDeliveries()

        XCTAssertEqual(model.deliveries.first?.state, .delivered)
        XCTAssertNotNil(model.sentAttachmentImage(
            forEntryId: "local-user-\(capture.delivery.id)",
            name: "release-check.jpg"
        ))
    }

    @MainActor
    func testExactTerminalReplayAppendsOnlyOneAssistantBubble() {
        let now = Date().timeIntervalSince1970 * 1000
        let model = AppModel()
        model.deliveries = [existingSessionDelivery(createdAt: now)]
        let terminal = AgentEvent(
            type: "agent.event",
            text: "Exactly-once terminal answer",
            requestId: nil,
            kind: "response",
            sessionId: "existing-session",
            originMessageId: "phone-message-1",
            createdAt: now + 20
        )

        model.receive(terminal)
        model.receive(terminal)

        let matching = model.activities["existing-session"]?.entries.filter {
            $0.text == terminal.text && $0.createdAt == terminal.createdAt
        } ?? []
        XCTAssertEqual(matching.count, 1)
    }

    @MainActor
    func testTerminalEventDoesNotDuplicateAnswerAlreadyLoadedFromProviderTranscript() {
        let now = Date().timeIntervalSince1970 * 1000
        let model = AppModel()
        model.deliveries = [existingSessionDelivery(createdAt: now)]
        model.activities["existing-session"] = SessionActivity(
            sessionId: "existing-session",
            agent: "codex",
            state: "idle",
            entries: [ActivityEntry(
                id: "provider-answer", kind: "final",
                text: "Already loaded answer", createdAt: now + 10
            )],
            generatedAt: now + 10
        )

        model.receive(AgentEvent(
            type: "agent.event",
            text: "Already loaded answer",
            requestId: nil,
            kind: "response",
            sessionId: "existing-session",
            originMessageId: "phone-message-1",
            createdAt: now + 20
        ))

        let matching = model.activities["existing-session"]?.entries.filter {
            $0.text == "Already loaded answer"
        } ?? []
        XCTAssertEqual(matching.map(\.id), ["provider-answer"])
        XCTAssertTrue(model.deliveries.isEmpty)
    }

    @MainActor
    func testTerminalNewTaskFailureWithoutSessionConsumesOriginDelivery() {
        let now = Date().timeIntervalSince1970 * 1000
        let model = AppModel()
        model.localOnlySessionIds = ["phone-stub"]
        model.deliveries = [existingSessionDelivery(
            createdAt: now,
            sessionId: "phone-stub",
            agent: "codex"
        )]

        model.receive(AgentEvent(
            type: "agent.event",
            text: "Codex failed to start",
            requestId: nil,
            kind: "response",
            sessionId: nil,
            originMessageId: "phone-message-1",
            createdAt: now + 20
        ))

        XCTAssertTrue(model.deliveries.isEmpty)
    }

    @MainActor
    func testLegacyUnkindedAgentEventConsumesOriginDelivery() {
        let now = Date().timeIntervalSince1970 * 1000
        let model = AppModel()
        model.deliveries = [existingSessionDelivery(createdAt: now)]

        model.receive(AgentEvent(
            type: "agent.event",
            text: "Legacy final answer",
            requestId: nil,
            kind: nil,
            sessionId: "existing-session",
            originMessageId: "phone-message-1",
            createdAt: now + 20
        ))

        XCTAssertTrue(model.deliveries.isEmpty)
    }

    func testUserMessageRelayTTLMatchesUnacknowledgedRetentionPhase() {
        let now = Date().timeIntervalSince1970 * 1000
        var row = existingSessionDelivery(createdAt: now)
        row.processingAcknowledgedAt = now
        XCTAssertEqual(
            DeliveryOutboxPolicy.terminalDeadline(for: row),
            now + 600_000
        )
        row.processingRetryStartedAt = now + 330_000
        XCTAssertEqual(
            DeliveryOutboxPolicy.terminalDeadline(for: row),
            now + 600_000
        )

        XCTAssertEqual(DeliveryOutboxPolicy.maximumLocalRetentionMs, 720_000)
        XCTAssertEqual(DeliveryOutboxPolicy.unacknowledgedRetentionMs, 120_000)
        XCTAssertEqual(DeliveryOutboxPolicy.userMessageRelayTTLSeconds, 2 * 60)
        XCTAssertEqual(
            DeliveryOutboxPolicy.userMessageRelayTTLSeconds * 1_000,
            DeliveryOutboxPolicy.unacknowledgedRetentionMs
        )
    }

}
