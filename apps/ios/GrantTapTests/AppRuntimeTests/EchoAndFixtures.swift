import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testRemoteUserEchoReconcilesOnlyItsOwnOptimisticBubble() {
        let model = AppModel()
        let now = Date().timeIntervalSince1970 * 1_000
        var first = existingSessionDelivery(
            createdAt: now - 2_000, id: "delivery-one", text: "same message",
            sessionId: "session-a"
        )
        var second = existingSessionDelivery(
            createdAt: now - 1_000, id: "delivery-two", text: "same message",
            sessionId: "session-a"
        )
        first.roomId = "room-a"
        second.roomId = "room-a"
        first.processingAcknowledgedAt = now - 1_900
        second.processingAcknowledgedAt = now - 900
        model.deliveries = [first, second]
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            .empty,
            pairing: testPairing(room: "room-a", deviceName: "Main Mac"),
            prefer: true,
            now: now - 3_000
        )
        model.rememberSessionSourceRoom("room-a", sessionId: "session-a")
        model.activities["session-a"] = SessionActivity(
            sessionId: "session-a",
            agent: "codex",
            state: "working",
            entries: [
                ActivityEntry(
                    id: "local-user-delivery-one", kind: "user",
                    text: "same message", createdAt: first.createdAt
                ),
                ActivityEntry(
                    id: "local-user-delivery-two", kind: "user",
                    text: "same message", createdAt: second.createdAt
                ),
            ],
            generatedAt: now - 500
        )

        model.applyActivity(
            SessionActivity(
                sessionId: "session-a",
                agent: "codex",
                state: "working",
                entries: [
                    ActivityEntry(
                        id: "provider-user-one", kind: "user",
                        text: "same message", createdAt: first.createdAt + 10
                    ),
                ],
                generatedAt: now
            ),
            sourceNamespace: "room-a"
        )

        let ids = Set(model.activities["session-a"]?.entries.map(\.id) ?? [])
        XCTAssertTrue(ids.contains("provider-user-one"))
        XCTAssertFalse(ids.contains("local-user-delivery-one"))
        XCTAssertTrue(ids.contains("local-user-delivery-two"))
    }

    @MainActor
    func testProviderSnapshotReplacesLocalUserAndTerminalEchoesAfterOutboxCompletion() {
        let model = AppModel()
        let now = Date().timeIntervalSince1970 * 1_000
        model.activities["session-a"] = SessionActivity(
            sessionId: "session-a",
            agent: "codex",
            state: "working",
            entries: [
                ActivityEntry(
                    id: "local-user-delivery-one", kind: "user",
                    text: "hello", createdAt: now
                ),
                ActivityEntry(
                    id: "agent-event-response-origin-delivery-one", kind: "message",
                    text: "hello back", createdAt: now + 1_000
                ),
            ],
            generatedAt: now + 1_000
        )

        model.applyActivity(SessionActivity(
            sessionId: "session-a",
            agent: "codex",
            state: "idle",
            entries: [
                ActivityEntry(
                    id: "provider-user", kind: "user",
                    text: "hello", createdAt: now + 10
                ),
                ActivityEntry(
                    id: "provider-answer", kind: "final",
                    text: "hello back", createdAt: now + 1_010
                ),
            ],
            generatedAt: now + 2_000
        ))

        let entries = model.activities["session-a"]?.entries ?? []
        XCTAssertEqual(entries.filter { $0.text == "hello" }.map(\.id), ["provider-user"])
        XCTAssertEqual(entries.filter { $0.text == "hello back" }.map(\.id), ["provider-answer"])
    }

    /// Semantic snapshots must not depend on JSONEncoder's unspecified key
    /// ordering. Byte-budget tests intentionally continue to use the production
    /// encoder and exact encoded size.
    func deterministicJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    func existingSessionDelivery(
        createdAt: Double,
        id: String = "phone-message-1",
        text: String = "Проверь доставку",
        sessionId: String = "existing-session",
        agent: String? = nil,
        requestId: String? = nil
    ) -> OutgoingDelivery {
        OutgoingDelivery(
            id: id,
            text: text,
            agent: agent,
            cwd: nil,
            sessionId: sessionId,
            requestId: requestId,
            roomId: "room-a",
            attachments: [],
            preferredMcp: nil,
            skill: nil,
            createdAt: createdAt,
            updatedAt: createdAt,
            attempts: 1,
            state: .sending,
            error: nil,
            nextRetryAt: nil
        )
    }

    func stubSession(id: String, at: Double) -> SessionInfo {
        SessionInfo(
            sessionId: id,
            agent: "grok",
            title: "Grok task",
            state: "working",
            startedAt: at,
            lastActivityAt: at,
            tokensSession: 0,
            tokensLastTurn: 0
        )
    }

    func testConnectionRegistry() -> ConnectionRegistry {
        ConnectionRegistryLogic.upsert(.empty, pairing: testPairing())
    }

    func testPairing(room: String = "room-a", deviceName: String = "Test Mac") -> Pairing {
        Pairing(
            relayUrl: "ws://127.0.0.1:1",
            room: room,
            role: "phone",
            deviceName: deviceName,
            senderId: "test-sender",
            myPublicKey: "test-public",
            mySecretKey: "test-secret",
            peerPublicKey: "test-peer"
        )
    }
}
