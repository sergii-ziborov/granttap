import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testManualRetryOfOldMessageSurvivesPruningAndReconnect() throws {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        model.connectionRegistry = testConnectionRegistry()
        model.roomRuntime["room-a"] = AppModel.RoomRuntime(socketUp: false)
        var delivery = existingSessionDelivery(createdAt: now - 172_800_000, id: "old-manual-retry")
        delivery.state = .failed
        delivery.attempts = 5
        model.deliveries = [delivery]

        model.retryDelivery(delivery.id)
        model.pruneStaleDeliveries()
        let queued = try XCTUnwrap(model.deliveries.first)
        XCTAssertEqual(queued.createdAt, delivery.createdAt)
        XCTAssertEqual(queued.id, delivery.id)
        XCTAssertEqual(queued.state, .queued)
        XCTAssertEqual(queued.attempts, 0)
        model.deliveries = try JSONDecoder().decode([OutgoingDelivery].self,
            from: JSONEncoder().encode(model.deliveries))
        model.roomRuntime["room-a"] = AppModel.RoomRuntime(socketUp: true)
        model.relaysByRoom["room-a"] = RelayClient(pairing: testPairing())
        model.retryQueuedDeliveries(forRoom: "room-a")
        XCTAssertEqual(model.deliveries.first?.attempts, 1)
    }

    @MainActor
    func testUnsentOfflineMessageStartsDeliveryWhenConnectionReturns() {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        model.connectionRegistry = testConnectionRegistry()
        model.roomRuntime["room-a"] = AppModel.RoomRuntime(socketUp: true)
        model.relaysByRoom["room-a"] = RelayClient(pairing: testPairing())
        var delivery = existingSessionDelivery(createdAt: now - 600_000, id: "offline-unsent")
        delivery.state = .queued
        delivery.attempts = 0
        model.deliveries = [delivery]
        model.retryQueuedDeliveries(forRoom: "room-a")
        XCTAssertEqual(model.deliveries.first?.id, delivery.id)
        XCTAssertEqual(model.deliveries.first?.attempts, 1)
        model.pruneStaleDeliveries()
        XCTAssertEqual(model.deliveries.first?.id, delivery.id,
                       "A first send after a long offline wait needs a fresh receipt window")
    }
}
