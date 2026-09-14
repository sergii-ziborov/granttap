import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testDeferredHelpersFailHeldRowsAndInterruptLiveGenerations() throws {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        model.connectionRegistry = testConnectionRegistry()
        model.localOnlySessionIds = ["local"]
        var local = existingSessionDelivery(
            createdAt: now - 10, id: "local", sessionId: "local"
        )
        local.updatedAt = now
        local.awaitingSessionRemap = false
        local.attemptGeneration = "generation"
        var held = existingSessionDelivery(
            createdAt: now, id: "held", sessionId: "local"
        )
        held.state = .queued
        held.awaitingSessionRemap = true
        held.attemptGeneration = "held-generation"
        model.deliveries = [local, held]
        model.liveDeliveryAttemptGenerations = ["generation", "held-generation"]

        XCTAssertEqual(model.localOriginSessionId(for: local), "local")
        XCTAssertNil(model.localOriginSessionId(for: held))
        XCTAssertEqual(model.deferredLifecycleAnchor(for: local), now)
        XCTAssertEqual(model.deferredLifecycleAnchor(for: held), held.createdAt)
        XCTAssertFalse(model.deliveryRoomIsUp("room-a"))
        model.roomRuntime["room-a"] = AppModel.RoomRuntime(socketUp: true)
        XCTAssertTrue(model.deliveryRoomIsUp("room-a"))

        model.markDeliveryAttemptsInterrupted(forRoom: "room-a")
        XCTAssertTrue(model.liveDeliveryAttemptGenerations.isEmpty)
        model.failDeferredFollowUps(forLocalSessionId: "missing")
        model.failDeferredFollowUps(forLocalSessionId: "local")
        let failed = try XCTUnwrap(model.deliveries.first { $0.id == "held" })
        XCTAssertEqual(failed.state, .failed)
        XCTAssertNil(failed.attemptGeneration)
        XCTAssertNil(failed.nextRetryAt)
        XCTAssertNotNil(failed.error)
    }

    @MainActor
    func testProcessingRetryAndExpiryCoverRecoveredAndTerminalRows() throws {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        model.connectionRegistry = testConnectionRegistry()
        model.roomRuntime["room-a"] = AppModel.RoomRuntime(socketUp: true)
        model.relaysByRoom["room-a"] = RelayClient(pairing: testPairing())

        var retry = existingSessionDelivery(
            createdAt: now - 1_000, id: "retry", sessionId: "native"
        )
        retry.state = .queued
        retry.attempts = 0
        retry.processingAcknowledgedAt = now - DeliveryOutboxPolicy.processingRetryDelayMs - 1
        retry.nextRetryAt = retry.processingAcknowledgedAt!
            + DeliveryOutboxPolicy.processingRetryDelayMs
        model.deliveries = [retry]
        model.retryQueuedDeliveries(forRoom: "room-a")
        let retried = try XCTUnwrap(model.deliveries.first)
        XCTAssertNotNil(retried.processingRetryStartedAt)
        XCTAssertGreaterThanOrEqual(retried.attempts, 1)

        var origin = existingSessionDelivery(
            createdAt: now - 1_000_000, id: "origin", sessionId: "local"
        )
        origin.state = .sending
        origin.processingAcknowledgedAt = now
            - DeliveryOutboxPolicy.processingRetryDelayMs
            - DeliveryOutboxPolicy.terminalAttemptWindowMs - 1_000
        origin.attempts = 0
        var follower = existingSessionDelivery(
            createdAt: now, id: "follower", sessionId: "local"
        )
        follower.state = .queued
        follower.awaitingSessionRemap = true
        model.localOnlySessionIds = ["local"]
        model.deliveries = [origin, follower]
        let deadline = try XCTUnwrap(DeliveryOutboxPolicy.terminalDeadline(for: origin))
        model.scheduleProcessingExpiry(origin.id, at: deadline)
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        XCTAssertEqual(model.deliveries.first { $0.id == "origin" }?.state, .failed)
        XCTAssertEqual(model.deliveries.first { $0.id == "follower" }?.state, .failed)
    }

    @MainActor
    func testDeferredResumeAndRetryGuardsIgnoreInvalidRows() {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        model.connectionRegistry = testConnectionRegistry()
        var held = existingSessionDelivery(
            createdAt: now, id: "held", sessionId: "local"
        )
        held.state = .queued
        held.awaitingSessionRemap = true
        var failed = held
        failed.awaitingSessionRemap = false
        failed.state = .failed
        model.deliveries = [held, failed]
        model.resumeDeferredFollowUps(["missing", held.id, failed.id])
        model.beginProcessingRetry("missing")
        model.retryQueuedDeliveries(forRoom: "other")
        XCTAssertEqual(model.deliveries.first?.attempts, held.attempts)
    }
}
