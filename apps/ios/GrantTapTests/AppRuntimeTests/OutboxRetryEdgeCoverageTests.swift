import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testRecoveredProcessingRetryReservationRunsNowAndSchedulesFutureRetry() throws {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        model.connectionRegistry = testConnectionRegistry()
        model.roomRuntime["room-a"] = AppModel.RoomRuntime(socketUp: true)
        model.relaysByRoom["room-a"] = RelayClient(pairing: testPairing())

        var ready = existingSessionDelivery(createdAt: now - 1_000, id: "ready")
        ready.state = .queued
        ready.attempts = 0
        ready.processingAcknowledgedAt = now - 500
        ready.processingRetryStartedAt = now - 400
        ready.nextRetryAt = now - 1
        model.deliveries = [ready]
        model.retryQueuedDeliveries()
        XCTAssertGreaterThan(model.deliveries[0].attempts, 0)

        var future = existingSessionDelivery(createdAt: now - 1_000, id: "future")
        future.state = .queued
        future.attempts = 0
        future.processingAcknowledgedAt = now - 500
        future.processingRetryStartedAt = now - 400
        future.nextRetryAt = now + 30
        model.deliveries = [future]
        model.retryQueuedDeliveries(forRoom: "room-a")
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        XCTAssertGreaterThan(model.deliveries[0].attempts, 0)
    }

    @MainActor
    func testScheduledProcessingRetryAndOrdinaryQueuedDeliveryEnterAttemptPath() {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        model.connectionRegistry = testConnectionRegistry()
        model.roomRuntime["room-a"] = AppModel.RoomRuntime(socketUp: true)
        model.relaysByRoom["room-a"] = RelayClient(pairing: testPairing())

        var acknowledged = existingSessionDelivery(createdAt: now - 1_000, id: "ack")
        acknowledged.state = .queued
        acknowledged.attempts = 0
        acknowledged.processingAcknowledgedAt = now - 100
        acknowledged.nextRetryAt = now + 20
        model.deliveries = [acknowledged]
        model.retryQueuedDeliveries()
        RunLoop.main.run(until: Date().addingTimeInterval(0.07))
        XCTAssertNotNil(model.deliveries[0].processingRetryStartedAt)
        XCTAssertGreaterThan(model.deliveries[0].attempts, 0)

        var ordinary = existingSessionDelivery(createdAt: now, id: "ordinary")
        ordinary.state = .queued
        ordinary.attempts = 0
        ordinary.processingAcknowledgedAt = nil
        model.deliveries = [ordinary]
        model.retryQueuedDeliveries()
        XCTAssertGreaterThan(model.deliveries[0].attempts, 0)
    }

    @MainActor
    func testExpiredProcessingAttemptDropsItsLiveGeneration() throws {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        var expired = existingSessionDelivery(
            createdAt: now - DeliveryOutboxPolicy.terminalLifecycleMs - 10_000,
            id: "expired-generation"
        )
        expired.processingAcknowledgedAt = expired.createdAt
        expired.processingRetryStartedAt = now - DeliveryOutboxPolicy.terminalAttemptWindowMs - 1_000
        expired.attemptGeneration = "live-expired"
        model.liveDeliveryAttemptGenerations = ["live-expired"]
        model.deliveries = [expired]
        let deadline = try XCTUnwrap(DeliveryOutboxPolicy.terminalDeadline(for: expired))
        model.scheduleProcessingExpiry(expired.id, at: deadline)
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        XCTAssertEqual(model.deliveries[0].state, .failed)
        XCTAssertFalse(model.liveDeliveryAttemptGenerations.contains("live-expired"))
    }
}
