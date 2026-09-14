import XCTest
@testable import GrantTap

/// A busy chat queues a phone message for up to 15 minutes, so its transcript
/// echo arrives long after the optimistic bubble was drawn. Reconciliation used
/// a 5-minute window anchored on send time, so the echo missed it and the same
/// message stayed on screen twice.
extension AppRuntimeTests {
    @MainActor
    func testAQueuedMessageReconcilesEvenWhenDeliveredMuchLater() {
        let model = AppModel()
        let now = Date().timeIntervalSince1970 * 1_000
        let sendAt = now - 12 * 60 * 1_000          // sent 12 minutes ago
        let deliveredAt = now - 30 * 1_000          // finally delivered just now

        var delivery = existingSessionDelivery(
            createdAt: sendAt, id: "queued-1", text: "проверь фото", sessionId: "session-q"
        )
        delivery.roomId = "room-a"
        delivery.state = .delivered
        delivery.updatedAt = deliveredAt
        delivery.processingAcknowledgedAt = deliveredAt
        model.deliveries = [delivery]
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            .empty,
            pairing: testPairing(room: "room-a", deviceName: "Main Mac"),
            prefer: true,
            now: sendAt - 1_000
        )
        model.rememberSessionSourceRoom("room-a", sessionId: "session-q")
        model.activities["session-q"] = SessionActivity(
            sessionId: "session-q", agent: "claude", state: "working",
            entries: [
                ActivityEntry(id: "local-user-queued-1", kind: "user",
                              text: "проверь фото", createdAt: sendAt),
            ],
            generatedAt: sendAt
        )

        // The provider transcript now carries that same line, stamped at the
        // moment the queued turn actually ran — 12 minutes after send.
        model.applyActivity(
            SessionActivity(
                sessionId: "session-q", agent: "claude", state: "working",
                entries: [
                    ActivityEntry(id: "claude-row-1", kind: "user",
                                  text: "проверь фото", createdAt: deliveredAt),
                ],
                generatedAt: now
            ),
            sourceNamespace: "room-a"
        )

        let userLines = model.activities["session-q"]?.entries
            .filter { $0.kind == "user" } ?? []
        XCTAssertEqual(userLines.count, 1, "a queued message must not render twice")
        XCTAssertEqual(userLines.first?.id, "claude-row-1", "the provider row is the survivor")
    }

    @MainActor
    func testTwoDifferentQueuedMessagesStayTwoMessages() {
        let model = AppModel()
        let now = Date().timeIntervalSince1970 * 1_000
        model.applyActivity(
            SessionActivity(
                sessionId: "session-two", agent: "codex", state: "idle",
                entries: [
                    ActivityEntry(id: "r1", kind: "user", text: "one", createdAt: now),
                    ActivityEntry(id: "r2", kind: "user", text: "two", createdAt: now + 1_000),
                ],
                generatedAt: now + 2_000
            )
        )
        XCTAssertEqual(model.activities["session-two"]?.entries.count, 2)
    }
}

extension AppRuntimeTests {
    @MainActor
    func testARelayedShortAnswerConvergesEvenAfterItsTranscriptRowAged() {
        let model = AppModel()
        let now = Date().timeIntervalSince1970 * 1_000
        // A durably-replayed "ok" the bridge keeps resending, minted long ago.
        model.activities["session-ok"] = SessionActivity(
            sessionId: "session-ok", agent: "claude", state: "idle",
            entries: [
                ActivityEntry(id: "agent-event-response-origin-m1", kind: "message",
                              text: "ok", createdAt: now - 40 * 60 * 1_000),
            ],
            generatedAt: now - 40 * 60 * 1_000
        )
        // The transcript now carries that same answer, stamped near its real time.
        model.applyActivity(
            SessionActivity(
                sessionId: "session-ok", agent: "claude", state: "idle",
                entries: [
                    ActivityEntry(id: "claude-ok", kind: "message", text: "ok",
                                  createdAt: now - 39 * 60 * 1_000),
                ],
                generatedAt: now
            )
        )
        let answers = model.activities["session-ok"]?.entries
            .filter { $0.text == "ok" } ?? []
        XCTAssertEqual(answers.count, 1, "a replayed answer must not hang as a duplicate")
        XCTAssertEqual(answers.first?.id, "claude-ok", "the transcript row is the survivor")
    }

    @MainActor
    func testTwoGenuineOkRepliesStayTwo() {
        let model = AppModel()
        let now = Date().timeIntervalSince1970 * 1_000
        model.applyActivity(
            SessionActivity(
                sessionId: "session-2ok", agent: "claude", state: "idle",
                entries: [
                    ActivityEntry(id: "r1", kind: "message", text: "ok", createdAt: now),
                    ActivityEntry(id: "r2", kind: "message", text: "ok", createdAt: now + 1_000),
                ],
                generatedAt: now + 2_000
            )
        )
        XCTAssertEqual(
            model.activities["session-2ok"]?.entries.filter { $0.text == "ok" }.count, 2,
            "the transcript keeps the real count; only relayed copies converge"
        )
    }
}
