import UIKit
import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testBackgroundWakeCompletionAndEmptySnapshotCleanup() {
        let model = AppModel()
        var results: [UIBackgroundFetchResult] = []
        model.handleRemoteWake { results.append($0) }
        model.handleRemoteWake { results.append($0) }
        XCTAssertEqual(model.backgroundWakeCompletions.count, 2)
        model.finishBackgroundWake(.newData)
        XCTAssertEqual(results, [.newData, .newData])
        XCTAssertTrue(model.backgroundWakeCompletions.isEmpty)
        model.finishBackgroundWake(.noData)

        model.sessionIdAliases["stub"] = "native"
        model.activities = [
            "stub": SessionActivity(
                sessionId: "stub", agent: "codex", state: "idle",
                entries: [], generatedAt: 1
            ),
            "native": SessionActivity(
                sessionId: "native", agent: "codex", state: "idle",
                entries: [], generatedAt: 1
            ),
            "kept": SessionActivity(
                sessionId: "kept", agent: "codex", state: "working",
                entries: [ActivityEntry(id: "e", kind: "message", text: "ok", createdAt: 1)],
                generatedAt: 1
            ),
        ]
        model.clearEmptyActivitySnapshot(sessionId: "stub")
        XCTAssertNil(model.activities["stub"])
        XCTAssertNil(model.activities["native"])
        XCTAssertNotNil(model.activities["kept"])
        model.clearEmptyActivitySnapshot(sessionId: "missing")
    }

    @MainActor
    func testSubscriptionsTrackSourcesAndRouteNudgesPerRoom() {
        let model = AppModel()
        let room = "subscription-room"
        let client = RelayClient(pairing: testPairing(room: room))
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            .empty, pairing: testPairing(room: room)
        )
        model.relaysByRoom[room] = client
        model.rememberSessionSourceRoom(room, sessionId: "session")

        model.subscribeSession("session", active: true, source: "first")
        model.subscribeSession("session", active: true, source: "second")
        XCTAssertEqual(model.activitySubscribers["session"], ["first", "second"])
        XCTAssertNotNil(model.activityHeartbeatTasks["session"])
        model.nudgeMacSessionScan(via: client)
        model.subscribeSession("session", active: false, source: "first")
        XCTAssertEqual(model.activitySubscribers["session"], ["second"])
        model.subscribeSession("session", active: false, source: "second")
        XCTAssertNil(model.activitySubscribers["session"])
        XCTAssertNil(model.activityHeartbeatTasks["session"])
        model.stopActivityHeartbeat("missing")

        let other = testPairing(room: "other-room")
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            model.connectionRegistry, pairing: other, prefer: false
        )
        model.sessionSourceRooms["ambiguous"] = [room, other.room]
        model.activitySubscribers = ["ambiguous": ["ui"], "unknown": ["ui"]]
        model.nudgeMacSessionScan(via: client)
        model.setRefreshHint("Updating")
        XCTAssertEqual(model.refreshHint, "Updating")
        model.setRefreshHint(nil)
        XCTAssertNil(model.refreshHint)
    }

    @MainActor
    func testRefreshSessionsCoversDemoUnpairedUpdatedAndOfflineResults() async {
        let model = AppModel()
        model.demoMode = true
        await model.refreshSessions()
        model.demoMode = false
        await model.refreshSessions()
        XCTAssertEqual(model.refreshHint, L("Not paired"))

        let room = "refresh-room"
        let client = RelayClient(pairing: testPairing(room: room))
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            .empty, pairing: testPairing(room: room)
        )
        model.relaysByRoom[room] = client
        model.relay = client
        model.roomRuntime[room] = AppModel.RoomRuntime(socketUp: true)
        model.connected = true
        let first = Task { @MainActor in await model.refreshSessions() }
        await waitForRefreshWaiter(model)
        model.sessions = [stubSession(id: "updated", at: 1)]
        model.lastSessionsGeneratedAt += 1
        model.completeSessionRefreshWaiters()
        await first.value
        XCTAssertTrue(model.refreshHint?.contains("Updated") == true)

        model.connected = false
        model.roomRuntime[room] = AppModel.RoomRuntime(socketUp: false)
        let second = Task { @MainActor in await model.refreshSessions() }
        await waitForRefreshWaiter(model)
        model.completeSessionRefreshWaiters()
        await second.value
        XCTAssertEqual(model.refreshHint, L("Still offline"))
        client.disconnect()
    }

    @MainActor
    private func waitForRefreshWaiter(_ model: AppModel) async {
        for _ in 0..<100 where model.sessionRefreshWaiters.isEmpty {
            await Task.yield()
        }
        XCTAssertFalse(model.sessionRefreshWaiters.isEmpty)
    }
}
