import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testForegroundRecoveryStartsOnlyWhenCatalogNeedsIt() {
        let model = AppModel()
        let now = Date().timeIntervalSince1970 * 1_000
        model.connectionRegistry = testConnectionRegistry()
        model.roomRuntime["room-a"] = AppModel.RoomRuntime(
            socketUp: true, socketUpSince: now - 200_000
        )
        var starts = 0
        model.recoverCatalogAfterForeground { starts += 1 }
        XCTAssertEqual(starts, 1)
        XCTAssertTrue(model.refreshAfterConnect)

        model.startDemo()
        model.refreshAfterConnect = false
        model.recoverCatalogAfterForeground { starts += 1 }
        XCTAssertEqual(starts, 1)
        XCTAssertFalse(model.refreshAfterConnect)
    }

    @MainActor
    func testRepairConnectionUsesExactInjectedComputerAndConnectedCopy() async {
        let model = AppModel()
        model.connectionRegistry = testConnectionRegistry()
        model.connected = true
        var repaired: String?
        await model.repairConnection(roomId: "room-a") { room in repaired = room }
        XCTAssertEqual(repaired, "room-a")
        XCTAssertTrue(model.refreshAfterConnect)
        XCTAssertTrue(model.refreshHint?.contains("waiting") == true)
    }

    @MainActor
    func testFixConnectionCoversDemoOfflineConnectedAndLiveStates() async {
        let model = AppModel()
        model.startDemo()
        await model.fixConnection()
        XCTAssertFalse(model.demoMode)

        await model.fixConnection()
        model.connectionRegistry = testConnectionRegistry()
        model.roomRuntime["room-a"] = AppModel.RoomRuntime(socketUp: false)
        model.connected = true
        var reconnects = 0
        await model.fixConnection(
            reconnect: { _ in reconnects += 1 }, wait: {}
        )
        XCTAssertEqual(reconnects, 1)
        XCTAssertTrue(model.refreshHint?.contains("waiting") == true)

        model.connected = false
        await model.fixConnection(
            reconnect: { _ in reconnects += 1 }, wait: {}
        )
        XCTAssertTrue(model.refreshHint?.contains("offline") == true)

        let now = Date().timeIntervalSince1970 * 1_000
        model.roomRuntime["room-a"] = AppModel.RoomRuntime(
            socketUp: true, socketUpSince: now, lastHeartbeatAt: now
        )
        var refreshes = 0
        await model.fixConnection(refresh: { refreshes += 1 })
        XCTAssertEqual(refreshes, 1)
    }

    @MainActor
    func testReconnectConnectionAttachesThenReusesItsExactRoomRelay() async {
        let model = AppModel()
        model.connectionRegistry = testConnectionRegistry()
        await model.reconnectConnection(roomId: "room-a", delayNanoseconds: 0)
        XCTAssertNotNil(model.relaysByRoom["room-a"])
        await model.reconnectConnection(roomId: "room-a", delayNanoseconds: 0)
        model.relaysByRoom["room-a"]?.disconnect()
    }
}
