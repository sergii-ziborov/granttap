import CryptoKit
import XCTest
@testable import GrantTap

/// A busy Mac is not a dead Mac. Liveness must come from the cheap heartbeat,
/// never from how long a full provider catalog scan happened to take — the
/// phone purges its visible chat list once it decides a computer is offline.
extension AppRuntimeTests {
    @MainActor
    private func livenessModel(
        room: String,
        catalogAgeMs: Double,
        heartbeatAgeMs: Double?
    ) -> AppModel {
        let model = AppModel()
        let now = Date().timeIntervalSince1970 * 1_000
        var registry = ConnectionRegistryLogic.upsert(
            .empty,
            pairing: testPairing(room: room),
            prefer: true,
            now: now - 600_000
        )
        registry = ConnectionRegistryLogic.noteCatalog(
            registry,
            roomId: room,
            generatedAt: now - catalogAgeMs,
            machineName: "busy.local"
        )
        model.connectionRegistry = registry
        model.roomRuntime[room] = AppModel.RoomRuntime(
            socketUp: true,
            socketUpSince: now - 600_000,
            lastHeartbeatAt: heartbeatAgeMs.map { now - $0 } ?? 0
        )
        return model
    }

    @MainActor
    func testFreshHeartbeatKeepsABusyMacLiveWhileItsCatalogLags() {
        let model = livenessModel(
            room: "heartbeat-live",
            catalogAgeMs: 240_000,
            heartbeatAgeMs: 8_000
        )
        XCTAssertEqual(model.connectionSnapshot.phase, .live)
        XCTAssertFalse(model.needsForegroundCatalogRecovery)
    }

    @MainActor
    func testMissingHeartbeatStillReportsMacOffline() {
        let model = livenessModel(
            room: "heartbeat-absent",
            catalogAgeMs: 240_000,
            heartbeatAgeMs: nil
        )
        XCTAssertEqual(model.connectionSnapshot.phase, .macOffline)
    }

    @MainActor
    func testExpiredHeartbeatStillReportsMacOffline() {
        let model = livenessModel(
            room: "heartbeat-expired",
            catalogAgeMs: 240_000,
            heartbeatAgeMs: 120_000
        )
        XCTAssertEqual(
            model.connectionSnapshot.phase,
            .macOffline,
            "stale liveness must fail closed, never linger as Live"
        )
    }

    @MainActor
    func testHeartbeatFromOneRoomNeverRevivesAnother() {
        let model = livenessModel(
            room: "heartbeat-own",
            catalogAgeMs: 240_000,
            heartbeatAgeMs: nil
        )
        let now = Date().timeIntervalSince1970 * 1_000
        model.roomRuntime["other-room"] = AppModel.RoomRuntime(
            socketUp: true,
            socketUpSince: now - 600_000,
            lastHeartbeatAt: now - 1_000
        )
        XCTAssertEqual(model.connectionSnapshot.phase, .macOffline)
    }

    @MainActor
    func testHeartbeatDoesNotForgeCatalogFreshness() {
        let model = livenessModel(
            room: "heartbeat-catalog",
            catalogAgeMs: 240_000,
            heartbeatAgeMs: 5_000
        )
        XCTAssertFalse(
            model.isMacCatalogFresh,
            "liveness is not a claim that the chat list is up to date"
        )
    }

    /// Swift seeds `String.hashValue` per process, so an id built from it changes
    /// on every relaunch and the same replayed event lands as a second bubble.
    func testAgentEventEntryIdIsStableAcrossProcesses() {
        let text = "Готово, всё собрано"
        let digest = SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(16)
        XCTAssertEqual(
            AppModel.agentEventEntryId(text: text, createdAt: 1_700_000_000_000),
            "agent-event-1700000000000-\(digest)"
        )
    }

    func testAgentEventEntryIdSeparatesDifferentTextAtTheSameInstant() {
        XCTAssertNotEqual(
            AppModel.agentEventEntryId(text: "one", createdAt: 5_000),
            AppModel.agentEventEntryId(text: "two", createdAt: 5_000)
        )
    }

    @MainActor
    func testProviderTranscriptAbsorbsAnUnboundRelayedAgentReply() {
        let model = AppModel()
        // A transcript this test persisted on an earlier run of the same
        // simulator would already hold the provider's row, and the count below
        // would read it as a duplicate that never was.
        model.activities = [:]
        let now = Date().timeIntervalSince1970 * 1_000
        let room = "echo-room"
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            .empty,
            pairing: testPairing(room: room),
            prefer: true,
            now: now - 10_000
        )
        model.rememberSessionSourceRoom(room, sessionId: "session-echo")
        // A relayed status line the provider log will repeat verbatim, minted
        // without an origin message — nothing binds it to a delivery.
        model.appendLocalChatEntry(
            sessionId: "session-echo",
            agent: "claude",
            entryId: AppModel.agentEventEntryId(text: "Собрал проект", createdAt: now),
            kind: "message",
            text: "Собрал проект",
            createdAt: now
        )
        XCTAssertEqual(model.activities["session-echo"]?.entries.count, 1)

        model.applyActivity(
            SessionActivity(
                sessionId: "session-echo",
                agent: "claude",
                state: "idle",
                entries: [
                    ActivityEntry(
                        id: "claude-row-1", kind: "message",
                        text: "Собрал проект", createdAt: now + 400
                    ),
                ],
                generatedAt: now + 1_000
            ),
            sourceNamespace: room
        )

        let entries = model.activities["session-echo"]?.entries ?? []
        XCTAssertEqual(entries.count, 1, "one answer must not render twice")
        XCTAssertEqual(entries.first?.id, "claude-row-1")
    }

    @MainActor
    func testRepeatedProviderAnswersAreNotCollapsedIntoOne() {
        let model = AppModel()
        model.activities = [:]
        let now = Date().timeIntervalSince1970 * 1_000
        model.applyActivity(
            SessionActivity(
                sessionId: "session-twice",
                agent: "codex",
                state: "idle",
                entries: [
                    ActivityEntry(id: "row-1", kind: "message", text: "ок", createdAt: now),
                    ActivityEntry(id: "row-2", kind: "message", text: "ок", createdAt: now + 900),
                ],
                generatedAt: now + 1_000
            )
        )
        XCTAssertEqual(
            model.activities["session-twice"]?.entries.count,
            2,
            "the agent genuinely said it twice"
        )
    }
}
