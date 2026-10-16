import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testCatalogRefreshCannotSpendRetriesWhileSocketSendIsStillActive() {
        let model = AppModel()
        model.connectionRegistry = testConnectionRegistry()
        model.roomRuntime["room-a"] = AppModel.RoomRuntime(socketUp: true)
        model.relaysByRoom["room-a"] = RelayClient(pairing: testPairing())
        let now = Date().timeIntervalSince1970 * 1_000
        var row = existingSessionDelivery(createdAt: now, id: "in-flight")
        row.state = .sending
        row.attempts = 1
        row.attemptGeneration = "active-send"
        model.liveDeliveryAttemptGenerations = ["active-send"]
        model.deliveries = [row]
        for _ in 0..<8 { model.retryQueuedDeliveries(forRoom: "room-a") }
        XCTAssertEqual(model.deliveries.first?.attempts, 1)
        XCTAssertEqual(model.deliveries.first?.attemptGeneration, "active-send")
        XCTAssertEqual(model.deliveries.first?.state, .sending)
    }

    @MainActor
    func testCatalogRefreshRespectsBothReceiptWaitAndTransportBackoff() {
        let model = AppModel()
        model.connectionRegistry = testConnectionRegistry()
        model.roomRuntime["room-a"] = AppModel.RoomRuntime(socketUp: true)
        model.relaysByRoom["room-a"] = RelayClient(pairing: testPairing())
        let now = Date().timeIntervalSince1970 * 1_000
        for state in [DeliveryState.queued, .sending] {
            var row = existingSessionDelivery(createdAt: now, id: "awaiting-confirmation")
            row.state = state
            row.attempts = 1
            row.nextRetryAt = now + 60_000
            model.deliveries = [row]
            for _ in 0..<8 { model.retryQueuedDeliveries(forRoom: "room-a") }
            XCTAssertEqual(model.deliveries.first?.attempts, 1)
            XCTAssertEqual(model.deliveries.first?.state, state)
        }
    }

    func testProcessingRecoveryWaitsUntilTheMachineLeaseAndProviderWindowHaveExpired() {
        XCTAssertGreaterThanOrEqual(DeliveryOutboxPolicy.providerTimeoutMs, 600_000)
        XCTAssertGreaterThan(DeliveryOutboxPolicy.machineProcessingLeaseMs, 600_000)
        XCTAssertGreaterThan(DeliveryOutboxPolicy.processingRetryDelayMs,
                             DeliveryOutboxPolicy.machineProcessingLeaseMs)
    }
}
