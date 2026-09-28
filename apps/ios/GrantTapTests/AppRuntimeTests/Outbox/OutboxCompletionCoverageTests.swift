import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testTransportCompletionGuardsSuccessRetryAndExhaustion() throws {
        let model = AppModel()
        let now = Date().timeIntervalSince1970 * 1_000
        model.deliveries = []
        model.deliveryAttemptFinished("missing", error: nil)
        var delivered = existingSessionDelivery(createdAt: 1, id: "delivered")
        delivered.state = .delivered
        model.deliveries = [delivered]
        model.deliveryAttemptFinished(delivered.id, error: nil)
        XCTAssertEqual(model.deliveries.first?.state, .delivered)

        var generated = existingSessionDelivery(createdAt: 2, id: "generated")
        generated.attemptGeneration = "current"
        model.deliveries = [generated]
        model.deliveryAttemptFinished(generated.id, error: nil, generation: "stale")
        XCTAssertEqual(model.deliveries.first?.attemptGeneration, "current")
        model.deliveryAttemptFinished(generated.id, error: nil)
        XCTAssertEqual(model.deliveries.first?.attemptGeneration, "current")
        model.liveDeliveryAttemptGenerations.insert("current")
        model.deliveryAttemptFinished(generated.id, error: nil, generation: "current")
        XCTAssertEqual(model.deliveries.first?.state, .sending)
        XCTAssertNotNil(model.deliveries.first?.nextRetryAt)

        var retry = existingSessionDelivery(createdAt: 3, id: "retry")
        retry.attempts = 1
        model.deliveries = [retry]
        model.deliveryAttemptFinished(retry.id, error: testDeliveryError())
        XCTAssertEqual(model.deliveries.first?.state, .queued)
        XCTAssertNotNil(model.deliveries.first?.nextRetryAt)

        var failed = existingSessionDelivery(createdAt: now, id: "failed")
        failed.attempts = model.maxDeliveryAttempts
        model.deliveries = [failed]
        model.deliveryAttemptFinished(failed.id, error: testDeliveryError())
        XCTAssertEqual(model.deliveries.first?.state, .failed)
        XCTAssertNil(model.deliveries.first?.nextRetryAt)

        var reflected = existingSessionDelivery(
            createdAt: 5, id: "reflected", text: "already sent", sessionId: "session"
        )
        reflected.attempts = model.maxDeliveryAttempts
        model.deliveries = [reflected]
        model.activities["session"] = SessionActivity(
            sessionId: "session", agent: "codex", state: "idle",
            entries: [ActivityEntry(
                id: "provider", kind: "user", text: "already sent", createdAt: 6
            )], generatedAt: 6
        )
        model.deliveryAttemptFinished(reflected.id, error: testDeliveryError())
        XCTAssertTrue(model.deliveries.isEmpty)
    }

    @MainActor
    func testAcknowledgedAttemptExpiredAndSuccessfulPathsRemainTerminalBounded() {
        let model = AppModel()
        let now = Date().timeIntervalSince1970 * 1_000
        var expired = existingSessionDelivery(
            createdAt: now - DeliveryOutboxPolicy.terminalLifecycleMs - 10_000,
            id: "expired", sessionId: "local"
        )
        expired.processingAcknowledgedAt = expired.createdAt
        expired.processingRetryStartedAt = now - DeliveryOutboxPolicy.terminalAttemptWindowMs - 1_000
        expired.attemptGeneration = "expired-generation"
        model.localOnlySessionIds = ["local"]
        model.deliveries = [expired]
        model.deliveryAttemptFinished(
            expired.id, error: testDeliveryError(), generation: "expired-generation"
        )
        XCTAssertEqual(model.deliveries.first?.state, .failed)
        XCTAssertNil(model.deliveries.first?.processingAcknowledgedAt)

        var acknowledged = existingSessionDelivery(createdAt: now, id: "acknowledged")
        acknowledged.processingAcknowledgedAt = now
        model.deliveries = [acknowledged]
        model.deliveryAttemptFinished(acknowledged.id, error: nil)
        XCTAssertEqual(model.deliveries.first?.state, .sending)
        XCTAssertNotNil(model.deliveries.first?.processingAcknowledgedAt)

        acknowledged.processingRetryStartedAt = now
        acknowledged.attemptGeneration = "success-generation"
        model.deliveries = [acknowledged]
        model.deliveryAttemptFinished(
            acknowledged.id, error: nil, generation: "success-generation"
        )
        XCTAssertEqual(model.deliveries.first?.state, .sending)
        XCTAssertNil(model.deliveries.first?.error)
    }

    @MainActor
    func testDeliveryReflectionAndInterruptedRecoveryBranches() {
        let model = AppModel()
        var row = existingSessionDelivery(
            createdAt: 1, id: "row", text: "hello", sessionId: "session"
        )
        XCTAssertFalse(model.outboxRowLooksDelivered(row))
        var noSession = row
        noSession = OutgoingDelivery(
            id: noSession.id, text: noSession.text, agent: noSession.agent,
            cwd: noSession.cwd, sessionId: nil, requestId: nil, roomId: nil,
            attachments: [], preferredMcp: nil, skill: nil,
            createdAt: 1, updatedAt: 1, attempts: 1, state: .sending,
            error: nil, nextRetryAt: nil
        )
        XCTAssertFalse(model.outboxRowLooksDelivered(noSession))
        model.connectionRegistry.preferredId = "other-room"
        XCTAssertFalse(model.outboxRowLooksDelivered(row))
        model.connectionRegistry.preferredId = nil
        model.activities["session"] = SessionActivity(
            sessionId: "session", agent: "codex", state: "idle",
            entries: [
                ActivityEntry(id: "local-user-row", kind: "user", text: "hello", createdAt: 1),
                ActivityEntry(id: "provider", kind: "message", text: "hello", createdAt: 2),
            ], generatedAt: 2
        )
        XCTAssertTrue(model.outboxRowLooksDelivered(row))

        let now = Date().timeIntervalSince1970 * 1_000
        row.processingAcknowledgedAt = now
        row.processingRetryStartedAt = now
        row.attemptGeneration = "interrupted"
        row.attempts = model.maxDeliveryAttempts
        model.deliveries = [row]
        model.reconcileInterruptedRecoveryAttempt(row.id)
        XCTAssertNil(model.deliveries.first?.attemptGeneration)
        XCTAssertEqual(model.deliveries.first?.state, .sending)
        model.reconcileInterruptedRecoveryAttempt("missing")
    }

    @MainActor
    func testImmediateReceiptAndTransportTimersRecheckDurableRows() {
        let model = AppModel()
        var reflected = existingSessionDelivery(
            createdAt: 1, id: "timer-reflected", text: "sent", sessionId: "session"
        )
        reflected.attempts = 1
        model.deliveries = [reflected]
        model.activities["session"] = SessionActivity(
            sessionId: "session", agent: "codex", state: "idle",
            entries: [ActivityEntry(
                id: "provider", kind: "user", text: "sent", createdAt: 2
            )], generatedAt: 2
        )
        model.deliveryAttemptFinished(
            reflected.id, error: nil, receiptRetryDelay: 0
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        XCTAssertTrue(model.deliveries.isEmpty)

        var retry = existingSessionDelivery(createdAt: 3, id: "timer-retry")
        retry.attempts = 1
        model.activities = [:]
        model.deliveries = [retry]
        model.deliveryAttemptFinished(
            retry.id, error: testDeliveryError(), transportRetryDelays: [0]
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        XCTAssertGreaterThanOrEqual(model.deliveries.first?.attempts ?? 0, 1)
    }

    private func testDeliveryError() -> NSError {
        NSError(domain: "coverage", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "offline",
        ])
    }
}
