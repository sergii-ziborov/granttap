import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testLocalStubFollowUpWaitsForNativeRemapInsteadOfStartingSecondTask() throws {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        // This suite runs against a real, reusable Simulator whose app data may
        // contain a stub alias from an earlier launch. The behavior under test
        // starts before any native remap, so isolate that precondition locally
        // instead of clearing the Simulator's persisted state.
        model.sessionIdAliases = [:]
        model.connectionRegistry = testConnectionRegistry()
        model.localOnlySessionIds = ["phone-stub"]
        model.sessionSourceRooms = ["phone-stub": ["room-a"]]
        model.sessions = [stubSession(id: "phone-stub", at: now)]
        model.deliveries = [existingSessionDelivery(
            createdAt: now,
            id: "origin-message",
            text: "Start the task",
            sessionId: "phone-stub",
            agent: "grok"
        )]

        model.sendMessage("Then verify the result", agent: "grok", sessionId: "phone-stub")

        let follower = try XCTUnwrap(model.deliveries.first {
            $0.text == "Then verify the result"
        })
        XCTAssertEqual(follower.state, .queued)
        XCTAssertEqual(follower.attempts, 0)
        XCTAssertEqual(follower.awaitingSessionRemap, true)
        XCTAssertEqual(follower.sessionId, "phone-stub")

        model.retryDelivery(follower.id)
        model.attemptDelivery(follower.id)
        XCTAssertEqual(model.deliveries.first { $0.id == follower.id }?.attempts, 0)
        XCTAssertEqual(
            model.deliveries.first { $0.id == follower.id }?.awaitingSessionRemap,
            true
        )
    }

    @MainActor
    func testDeferredLocalFollowUpSurvivesRelaunchAndReconnectRetry() throws {
        let now = Date().timeIntervalSince1970 * 1_000
        var follower = existingSessionDelivery(
            createdAt: now - DeliveryOutboxPolicy.unacknowledgedRetentionMs - 1_000,
            id: "deferred-follow-up",
            text: "Second message",
            sessionId: "phone-stub",
            agent: "grok"
        )
        follower.state = .queued
        follower.attempts = 0
        follower.attemptGeneration = nil
        follower.awaitingSessionRemap = true
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("granttap-deferred-follow-up-\(UUID().uuidString)",
                                    isDirectory: true)
        let file = root.appendingPathComponent("outgoing-deliveries.json")
        defer { try? FileManager.default.removeItem(at: root) }

        DeliveryPersistence.save([follower], to: file)
        let reloaded = try XCTUnwrap(DeliveryPersistence.load(from: file).first)
        let model = AppModel()
        model.connectionRegistry = testConnectionRegistry()
        model.roomRuntime["room-a"] = AppModel.RoomRuntime(socketUp: true)
        model.localOnlySessionIds = ["phone-stub"]
        model.deliveries = [reloaded]

        model.retryQueuedDeliveries(forRoom: "room-a")

        XCTAssertEqual(model.deliveries.first?.state, .queued)
        XCTAssertEqual(model.deliveries.first?.attempts, 0)
        XCTAssertEqual(model.deliveries.first?.awaitingSessionRemap, true)
    }

    @MainActor
    func testNativeRemapReleasesDeferredFollowUpWithProviderAndOrderIntact() throws {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        model.connectionRegistry = testConnectionRegistry()
        model.localOnlySessionIds = ["phone-stub"]
        model.sessions = [stubSession(id: "phone-stub", at: now)]
        var follower = existingSessionDelivery(
            createdAt: now - DeliveryOutboxPolicy.unacknowledgedRetentionMs - 1_000,
            id: "deferred-follow-up",
            text: "Second message",
            sessionId: "phone-stub",
            agent: "grok"
        )
        follower.state = .queued
        follower.attempts = 0
        follower.attemptGeneration = nil
        follower.awaitingSessionRemap = true
        model.deliveries = [
            follower,
            existingSessionDelivery(
                createdAt: now - DeliveryOutboxPolicy.unacknowledgedRetentionMs - 2_000,
                id: "origin-message",
                text: "First message",
                sessionId: "phone-stub",
                agent: "grok"
            ),
        ]

        model.remapLocalSession(from: "phone-stub", to: "native-session")
        // Simulate termination after the atomic rewrite but before a live relay
        // could send the released row. Relaunch pruning must retain it.
        model.deliveries = try JSONDecoder().decode(
            [OutgoingDelivery].self,
            from: JSONEncoder().encode(model.deliveries)
        )
        model.pruneStaleDeliveries()

        let released = try XCTUnwrap(model.deliveries.first {
            $0.id == "deferred-follow-up"
        })
        XCTAssertEqual(released.sessionId, "native-session")
        XCTAssertEqual(released.awaitingSessionRemap, false)
        XCTAssertEqual(released.state, .queued)
        XCTAssertEqual(released.attempts, 0)
        let payload = model.wireUserMessage(for: released)
        XCTAssertEqual(payload.sessionId, "native-session")
        XCTAssertEqual(payload.agent, "grok")
        XCTAssertEqual(payload.text, "Second message")
    }

    @MainActor
    func testNativeRemapDispatchesDeferredFollowUpsOldestFirst() {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        model.connectionRegistry = testConnectionRegistry()
        model.roomRuntime["room-a"] = AppModel.RoomRuntime(socketUp: true)
        model.relaysByRoom["room-a"] = RelayClient(pairing: testPairing())
        model.localOnlySessionIds = ["phone-stub"]
        model.sessions = [stubSession(id: "phone-stub", at: now)]
        var older = existingSessionDelivery(
            createdAt: now + 1,
            id: "older-01-message",
            text: "Second message",
            sessionId: "phone-stub",
            agent: "grok"
        )
        older.state = .queued
        older.attempts = 0
        older.attemptGeneration = nil
        older.awaitingSessionRemap = true
        var newer = existingSessionDelivery(
            createdAt: now + 2,
            id: "newer-02-message",
            text: "Third message",
            sessionId: "phone-stub",
            agent: "grok"
        )
        newer.state = .queued
        newer.attempts = 0
        newer.attemptGeneration = nil
        newer.awaitingSessionRemap = true
        model.deliveries = [
            newer,
            older,
            existingSessionDelivery(
                createdAt: now,
                id: "origin-message",
                text: "First message",
                sessionId: "phone-stub",
                agent: "grok"
            ),
        ]

        model.remapLocalSession(from: "phone-stub", to: "native-session")

        let chronologicalWireLog = model.log
            .filter { $0.hasPrefix("outbox.wire") }
            .reversed()
        XCTAssertEqual(Array(chronologicalWireLog), [
            "outbox.wire id=older-01 session=native-s agent=grok localOnly=false",
            "outbox.wire id=newer-02 session=native-s agent=grok localOnly=false",
        ])
        XCTAssertEqual(
            model.deliveries.filter { $0.id == older.id || $0.id == newer.id }
                .map(\.attempts),
            [1, 1]
        )
    }

    @MainActor
    func testTerminalNewTaskFailureMakesDeferredFollowUpVisibleAndRetryable() throws {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        model.connectionRegistry = testConnectionRegistry()
        model.localOnlySessionIds = ["phone-stub"]
        model.sessions = [stubSession(id: "phone-stub", at: now)]
        var follower = existingSessionDelivery(
            createdAt: now + 1,
            id: "deferred-follow-up",
            text: "Second message",
            sessionId: "phone-stub",
            agent: "grok"
        )
        follower.state = .queued
        follower.attempts = 0
        follower.attemptGeneration = nil
        follower.awaitingSessionRemap = true
        model.deliveries = [
            follower,
            existingSessionDelivery(
                createdAt: now,
                id: "origin-message",
                text: "First message",
                sessionId: "phone-stub",
                agent: "grok"
            ),
        ]

        model.receive(AgentEvent(
            type: "agent.event",
            text: "Grok Build failed to start",
            requestId: nil,
            kind: "response",
            sessionId: nil,
            originMessageId: "origin-message",
            createdAt: now + 2
        ))

        let failed = try XCTUnwrap(model.deliveries.first {
            $0.id == "deferred-follow-up"
        })
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(failed.awaitingSessionRemap, true)
        XCTAssertEqual(failed.attempts, 0)
        XCTAssertNotNil(failed.error)
        XCTAssertFalse(model.deliveries.contains { $0.id == "origin-message" })
        XCTAssertFalse(model.log.contains { $0.contains("id=deferred") })

        let relay = RelayClient(pairing: testPairing())
        model.relaysByRoom["room-a"] = relay
        model.roomRuntime["room-a"] = AppModel.RoomRuntime(socketUp: true, socketUpSince: now)
        model.retryDelivery(failed.id)

        let retried = try XCTUnwrap(model.deliveries.first {
            $0.id == "deferred-follow-up"
        })
        XCTAssertEqual(retried.awaitingSessionRemap, false)
        XCTAssertEqual(retried.attempts, 1)
        XCTAssertNotEqual(retried.state, .failed)
    }

}
