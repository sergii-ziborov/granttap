import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testRelayReceiptPersistsAcrossRestartWithoutWaitingForComputerOrResending() throws {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        model.connectionRegistry = testConnectionRegistry()
        model.roomRuntime["room-a"] = AppModel.RoomRuntime(socketUp: false)
        var row = existingSessionDelivery(createdAt: now - 86_400_000, id: "relay-saved-offline")
        row.state = .sending
        row.attempts = 1
        model.deliveries = [row]
        model.deliveryAttemptFinished(row.id, error: nil, relayStored: true)
        XCTAssertNotNil(model.deliveries[0].relayStoredAt)
        XCTAssertNil(model.deliveries[0].nextRetryAt)
        XCTAssertEqual(TaskRoutePresentation.deliveryStatus(model.deliveries[0], route: nil), L("Saved on relay"))
        model.deliveries = try JSONDecoder().decode([OutgoingDelivery].self,
            from: JSONEncoder().encode(model.deliveries))
        model.pruneStaleDeliveries()
        model.attemptDelivery(row.id)
        XCTAssertEqual(model.deliveries.first?.attempts, 1)
        XCTAssertEqual(model.deliveries.first?.id, row.id)
    }

    @MainActor
    func testRelayStorageNeverErasesNativeFailureOrItsProcessingDeadline() {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        var row = existingSessionDelivery(createdAt: now, id: "relay-native-result")
        row.state = .failed
        row.error = "Native rejection"
        model.deliveries = [row]
        model.deliveryAttemptFinished(row.id, error: nil, relayStored: true)
        XCTAssertEqual(model.deliveries[0].error, "Native rejection")
        XCTAssertNil(model.deliveries[0].relayStoredAt)
        model.deliveries[0].state = .sending
        model.deliveries[0].processingAcknowledgedAt = now
        model.deliveryAttemptFinished(row.id, error: nil, relayStored: true)
        XCTAssertEqual(model.deliveries[0].processingAcknowledgedAt, now)
        XCTAssertNil(model.deliveries[0].relayStoredAt)
    }
}
