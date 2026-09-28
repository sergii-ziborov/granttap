import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testAcceptedReceiptKeepsExistingSessionDeliverySending() {
        let now = Date().timeIntervalSince1970 * 1000
        let model = AppModel()
        model.deliveries = [existingSessionDelivery(createdAt: now)]

        model.receive(DeliveryReceipt(
            type: "delivery.receipt",
            messageId: "phone-message-1",
            sessionId: "existing-session",
            status: "accepted",
            error: nil,
            receivedAt: now + 10
        ), fromRoom: "room-a")

        XCTAssertEqual(model.deliveries.map(\.id), ["phone-message-1"])
        XCTAssertEqual(model.deliveries.first?.state, .sending)
        XCTAssertEqual(model.deliveries.first?.attempts, 0)
        let retryAt = try? XCTUnwrap(model.deliveries.first?.nextRetryAt)
        XCTAssertNotNil(retryAt)
        if let retryAt {
            XCTAssertGreaterThanOrEqual(retryAt - now, 330_000)
            XCTAssertLessThanOrEqual(retryAt - now, 331_000)
        }
    }

    @MainActor
    func testAcceptedReceiptKeepsNewTaskStubRetryableForTerminalRemap() {
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

        XCTAssertEqual(model.deliveries.map(\.id), ["phone-message-1"])
        XCTAssertEqual(model.deliveries.first?.sessionId, "phone-stub")
        XCTAssertEqual(model.deliveries.first?.state, .sending)
        XCTAssertEqual(model.deliveries.first?.attempts, 0)
        XCTAssertNotNil(model.deliveries.first?.nextRetryAt)
    }

    @MainActor
    func testDuplicateAcceptedReceiptDoesNotExtendProcessingRetryDeadline() throws {
        let now = Date().timeIntervalSince1970 * 1000
        let model = AppModel()
        model.deliveries = [existingSessionDelivery(createdAt: now)]
        let first = DeliveryReceipt(
            type: "delivery.receipt",
            messageId: "phone-message-1",
            sessionId: "existing-session",
            status: "accepted",
            error: nil,
            receivedAt: now + 10
        )

        model.receive(first, fromRoom: "room-a")
        let firstRetryAt = try XCTUnwrap(model.deliveries.first?.nextRetryAt)
        model.receive(DeliveryReceipt(
            type: first.type,
            messageId: first.messageId,
            sessionId: first.sessionId,
            status: first.status,
            error: nil,
            receivedAt: now + 120_000
        ), fromRoom: "room-a")

        XCTAssertEqual(model.deliveries.first?.nextRetryAt, firstRetryAt)
        XCTAssertEqual(model.deliveries.first?.attempts, 0)
    }

    @MainActor
    func testLateTransportCompletionCannotShortenProcessingDeadline() throws {
        let now = Date().timeIntervalSince1970 * 1000
        let model = AppModel()
        model.deliveries = [existingSessionDelivery(createdAt: now)]
        model.receive(DeliveryReceipt(
            type: "delivery.receipt",
            messageId: "phone-message-1",
            sessionId: "existing-session",
            status: "accepted",
            error: nil,
            receivedAt: now + 10
        ), fromRoom: "room-a")
        let retryAt = try XCTUnwrap(model.deliveries.first?.nextRetryAt)

        model.deliveryAttemptFinished(
            "phone-message-1",
            error: NSError(domain: "test", code: 1)
        )

        XCTAssertEqual(model.deliveries.first?.state, .sending)
        XCTAssertEqual(model.deliveries.first?.attempts, 0)
        XCTAssertEqual(model.deliveries.first?.nextRetryAt, retryAt)
        XCTAssertNil(model.deliveries.first?.error)
    }

    @MainActor
    func testRecoveryTransportErrorRetriesSameMessageWithinAbsoluteDeadlineAndGeneration() throws {
        let now = Date().timeIntervalSince1970 * 1000
        let model = AppModel()
        var row = existingSessionDelivery(createdAt: now - 331_000)
        row.processingAcknowledgedAt = now - 331_000
        row.processingRetryStartedAt = now - 1_000
        row.attempts = 1
        row.attemptGeneration = "recovery-generation"
        model.deliveries = [row]
        let deadline = try XCTUnwrap(DeliveryOutboxPolicy.terminalDeadline(for: row))

        let beforeStaleCallback = try deterministicJSON(model.deliveries)
        model.deliveryAttemptFinished(
            row.id,
            error: NSError(domain: "test", code: 1),
            generation: "stale-generation"
        )
        XCTAssertEqual(try deterministicJSON(model.deliveries), beforeStaleCallback)

        model.deliveryAttemptFinished(
            row.id,
            error: NSError(domain: "test", code: 2),
            generation: "recovery-generation"
        )

        let retry = try XCTUnwrap(model.deliveries.first)
        XCTAssertEqual(retry.id, row.id)
        XCTAssertEqual(retry.state, .queued)
        XCTAssertEqual(retry.attempts, 1)
        XCTAssertNil(retry.attemptGeneration)
        XCTAssertEqual(retry.processingRetryStartedAt, row.processingRetryStartedAt)
        XCTAssertEqual(DeliveryOutboxPolicy.terminalDeadline(for: retry), deadline)
        let retryAt = try XCTUnwrap(retry.nextRetryAt)
        XCTAssertGreaterThan(retryAt, now)
        XCTAssertLessThan(retryAt, deadline)

        model.deliveries[0].attempts = model.maxDeliveryAttempts
        model.deliveries[0].state = .sending
        model.deliveries[0].nextRetryAt = nil
        model.deliveries[0].attemptGeneration = "last-generation"
        model.deliveryAttemptFinished(
            row.id,
            error: NSError(domain: "test", code: 3),
            generation: "last-generation"
        )
        XCTAssertEqual(model.deliveries.first?.state, .sending)
        XCTAssertNil(model.deliveries.first?.nextRetryAt)
        XCTAssertEqual(DeliveryOutboxPolicy.terminalDeadline(for: model.deliveries[0]), deadline)
    }

    @MainActor
    func testRelaunchRequeuesInterruptedRecoveryGenerationWithoutMovingDeadline() throws {
        let now = Date().timeIntervalSince1970 * 1000
        let model = AppModel()
        var row = existingSessionDelivery(createdAt: now - 331_000)
        row.processingAcknowledgedAt = now - 331_000
        row.processingRetryStartedAt = now - 1_000
        row.attempts = 1
        row.state = .sending
        row.attemptGeneration = "persisted-before-crash"
        model.deliveries = [row]
        let deadline = try XCTUnwrap(DeliveryOutboxPolicy.terminalDeadline(for: row))

        model.retryQueuedDeliveries()

        let recovered = try XCTUnwrap(model.deliveries.first)
        XCTAssertEqual(recovered.id, row.id)
        XCTAssertEqual(recovered.state, .queued)
        XCTAssertEqual(recovered.attempts, 1)
        XCTAssertNil(recovered.attemptGeneration)
        XCTAssertEqual(DeliveryOutboxPolicy.terminalDeadline(for: recovered), deadline)

        let beforeStaleCallback = try deterministicJSON(model.deliveries)
        model.deliveryAttemptFinished(
            row.id,
            error: NSError(domain: "test", code: 4),
            generation: "persisted-before-crash"
        )
        XCTAssertEqual(try deterministicJSON(model.deliveries), beforeStaleCallback)
    }

    @MainActor
    func testSocketRestartMarksRecoveryGenerationInterruptedForSameIdResend() throws {
        let now = Date().timeIntervalSince1970 * 1000
        let model = AppModel()
        var row = existingSessionDelivery(createdAt: now - 331_000)
        row.processingAcknowledgedAt = now - 331_000
        row.processingRetryStartedAt = now - 1_000
        row.attempts = 1
        row.state = .sending
        row.attemptGeneration = "live-before-socket-restart"
        model.deliveries = [row]
        model.liveDeliveryAttemptGenerations = ["live-before-socket-restart"]
        let deadline = try XCTUnwrap(DeliveryOutboxPolicy.terminalDeadline(for: row))

        model.markDeliveryAttemptsInterrupted(forRoom: "room-a")
        model.retryQueuedDeliveries(forRoom: "room-a")

        let recovered = try XCTUnwrap(model.deliveries.first)
        XCTAssertEqual(recovered.id, row.id)
        XCTAssertEqual(recovered.state, .queued)
        XCTAssertEqual(recovered.attempts, 1)
        XCTAssertNil(recovered.attemptGeneration)
        XCTAssertFalse(
            model.liveDeliveryAttemptGenerations.contains("live-before-socket-restart")
        )
        XCTAssertEqual(DeliveryOutboxPolicy.terminalDeadline(for: recovered), deadline)
    }

    @MainActor
    func testAcceptedProcessingReceiptDoesNotSpeculativelyRecordCapabilityUsage() {
        let now = Date().timeIntervalSince1970 * 1000
        let unique = UUID().uuidString.lowercased()
        let mcpName = "disabled-mcp-\(unique)"
        let skillName = "failed-skill-\(unique)"
        let messageId = "capability-message-\(unique)"
        let model = AppModel()
        model.deliveries = [OutgoingDelivery(
            id: messageId,
            text: "Do not count selected capabilities before provider evidence",
            agent: nil,
            cwd: nil,
            sessionId: "existing-session",
            requestId: nil,
            roomId: "room-a",
            attachments: [],
            preferredMcp: mcpName,
            skill: skillName,
            createdAt: now,
            updatedAt: now,
            attempts: 1,
            state: .sending,
            error: nil,
            nextRetryAt: nil
        )]

        model.receive(DeliveryReceipt(
            type: "delivery.receipt",
            messageId: messageId,
            sessionId: "existing-session",
            status: "accepted",
            error: nil,
            receivedAt: now + 1
        ), fromRoom: "room-a")

        XCTAssertFalse(CapabilityUsageStore.shared.events.contains {
            ($0.kind == .mcp && $0.name == mcpName)
                || ($0.kind == .skill && $0.name == skillName)
        })
    }

}
