import UIKit
import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testCatalogApplyPurgesDemoKeepsDeliveryStubAndFiltersExistingHistory() {
        let model = AppModel()
        let now = Date().timeIntervalSince1970 * 1_000
        let demo = runtimeSession(id: AppModelDemoFixtures.codexSessionId, at: now)
        let held = runtimeSession(id: "session-held-coverage", at: now)
        let history = runtimeSession(id: "session-history-coverage", at: now - 10)
        var delivery = existingSessionDelivery(
            createdAt: now, id: "held-row", sessionId: held.sessionId
        )
        delivery.state = .failed
        model.sessions = [demo, held]
        model.sessionHistory = [history]
        model.archivedSessionIds = [history.sessionId]
        model.activities[demo.sessionId] = runtimeActivity(id: demo.sessionId, entries: [])
        model.deliveries = [delivery]
        model.applySessionsStatus(SessionsStatus(
            machine: "Mac", sessions: [], history: [],
            tokensRecent: 0, tokenWindowHours: 12, generatedAt: now
        ))
        XCTAssertEqual(model.sessions.map(\.sessionId), [held.sessionId])
        XCTAssertTrue(model.sessionHistory.isEmpty)
        XCTAssertNil(model.activities[demo.sessionId])
    }

    @MainActor
    func testEmptyCatalogTickRetainsRealLiveRowsWhenPreferredComputerIsFresh() {
        let model = AppModel()
        let now = Date().timeIntervalSince1970 * 1_000
        model.connectionRegistry = ConnectionRegistryLogic.noteCatalog(
            testConnectionRegistry(), roomId: "room-a", generatedAt: now,
            machineName: "Mac"
        )
        model.roomRuntime["room-a"] = AppModel.RoomRuntime(
            socketUp: true, socketUpSince: now - 1_000, lastHeartbeatAt: now
        )
        let live = runtimeSession(id: "session-live-coverage", at: now)
        model.sessions = [live]
        model.applySessionsStatus(SessionsStatus(
            machine: "Mac", sessions: [], history: nil,
            tokensRecent: 0, tokenWindowHours: 12, generatedAt: now + 1
        ))
        XCTAssertEqual(model.sessions.map(\.sessionId), [live.sessionId])
    }

    @MainActor
    func testActivityApplyStoresEmptyKeepsLoadedAndSkipsIdenticalSnapshots() {
        let model = AppModel()
        let empty = runtimeActivity(id: "empty", entries: [])
        model.applyActivity(empty)
        XCTAssertNil(model.activities["empty"], "an unopened chat must not store an empty catalog ack")
        model.subscribeSession("empty", active: true, source: "phone-chat:empty")
        model.applyActivity(empty)
        XCTAssertNotNil(model.activities["empty"])

        let loaded = runtimeActivity(id: "loaded", entries: [
            ActivityEntry(id: "entry", kind: "message", text: "done", createdAt: 1),
        ])
        model.activities["loaded"] = loaded
        model.applyActivity(runtimeActivity(id: "loaded", entries: []))
        XCTAssertEqual(model.activities["loaded"]?.entries.count, 1)
        model.applyActivity(loaded)
        XCTAssertEqual(model.activities["loaded"]?.entries.count, 1)
    }

    @MainActor
    func testReceiptRejectsWrongScopeMigratesLegacyAndFailsDeferredFollowers() {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        var wrongRoom = existingSessionDelivery(createdAt: now, id: "wrong-room")
        model.deliveries = [wrongRoom]
        model.receive(runtimeReceipt(id: wrongRoom.id), fromRoom: "other")
        XCTAssertEqual(model.deliveries[0].state, .sending)

        wrongRoom.roomId = nil
        wrongRoom.attemptGeneration = "live"
        model.liveDeliveryAttemptGenerations = ["live"]
        model.deliveries = [wrongRoom]
        model.receive(runtimeReceipt(id: wrongRoom.id, session: "other-session"), fromRoom: "room-a")
        XCTAssertEqual(model.deliveries[0].roomId, "room-a")
        XCTAssertEqual(model.deliveries[0].state, .sending)

        var rejected = existingSessionDelivery(
            createdAt: now, id: "rejected", sessionId: "local"
        )
        rejected.state = .sending
        rejected.attemptGeneration = "rejected-live"
        var follower = existingSessionDelivery(
            createdAt: now + 1, id: "follower", sessionId: "local"
        )
        follower.state = .queued
        follower.awaitingSessionRemap = true
        model.localOnlySessionIds = ["local"]
        model.deliveries = [rejected, follower]
        model.receive(runtimeReceipt(
            id: rejected.id, session: "local", status: "rejected", error: "blocked"
        ), fromRoom: "room-a")
        XCTAssertEqual(model.deliveries.first { $0.id == "rejected" }?.state, .failed)
        XCTAssertEqual(model.deliveries.first { $0.id == "follower" }?.state, .failed)
    }

    @MainActor
    func testAcceptedReceiptAfterProcessingRetryClearsNextRetry() {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        var row = existingSessionDelivery(createdAt: now, id: "processing")
        row.processingAcknowledgedAt = now - 1_000
        row.processingRetryStartedAt = now - 500
        row.nextRetryAt = now + 10_000
        model.deliveries = [row]
        model.receive(runtimeReceipt(id: row.id), fromRoom: "room-a")
        XCTAssertNil(model.deliveries[0].nextRetryAt)
    }

    @MainActor
    func testWakeTargetsEveryRoomAndLiveDecisionUsesPinnedRelay() {
        let model = AppModel()
        let client = RelayClient(pairing: testPairing())
        model.connectionRegistry = testConnectionRegistry()
        model.relaysByRoom["room-a"] = client
        var wake: UIBackgroundFetchResult?
        model.handleRemoteWake { wake = $0 }
        XCTAssertEqual(model.backgroundWakeCompletions.count, 1)
        model.finishBackgroundWake(.newData)
        XCTAssertEqual(wake, .newData)

        model.requestSourceRoom["decision"] = "room-a"
        model.markDecisionInFlight("decision", decision: "allow", sessionId: "session")
        model.deliverDecision(
            requestId: "decision", decision: "allow", by: "phone",
            sessionId: "session", title: "Run", agent: "codex"
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        XCTAssertNil(model.approvalDecisionsInFlight["decision"])
    }

    private func runtimeSession(id: String, at: Double) -> SessionInfo {
        SessionInfo(
            sessionId: id, agent: "codex", title: "Coverage task", state: "working",
            startedAt: at, lastActivityAt: at, tokensSession: 0, tokensLastTurn: 0
        )
    }

    private func runtimeActivity(id: String, entries: [ActivityEntry]) -> SessionActivity {
        SessionActivity(
            sessionId: id, agent: "codex", state: "working",
            entries: entries, generatedAt: 1
        )
    }

    private func runtimeReceipt(
        id: String, session: String? = "existing-session",
        status: String = "accepted", error: String? = nil
    ) -> DeliveryReceipt {
        DeliveryReceipt(
            type: "delivery.receipt", messageId: id, sessionId: session,
            status: status, error: error, receivedAt: 1
        )
    }
}
