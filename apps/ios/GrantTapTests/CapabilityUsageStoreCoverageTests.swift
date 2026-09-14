import XCTest
@testable import GrantTap

@MainActor
final class CapabilityUsageStoreCoverageTests: XCTestCase {
    private let store = CapabilityUsageStore.shared

    override func setUp() {
        store.clear()
    }

    override func tearDown() {
        store.clear()
    }

    func testRecordNormalizesScopesAndUpdatesAnExistingObservation() throws {
        let now = Date().timeIntervalSince1970 * 1_000 + 1_000
        store.record(.cli, name: "  ", sessionId: "session", sourceId: "empty",
                     createdAt: now)
        XCTAssertTrue(store.events.isEmpty)

        store.record(
            .cli, name: " Bash ", sessionId: " session-a ", sourceId: "call-a",
            createdAt: now, toolName: "shell", commandPreview: " npm   test\n",
            estimatedContextTokens: 20, estimatedBaselineTokens: 50,
            durationMs: 100, outcome: .success, errorClass: nil,
            sourceNamespace: " room-a ", agent: "Codex", model: " gpt-5 ",
            resource: CapabilityResourceUsage(
                attribution: .measured, cpuTimeMs: 24, peakRssBytes: 112_000_000
            )
        )
        let first = try XCTUnwrap(store.events.first)
        XCTAssertEqual(first.sourceId, "room-a:call-a")
        XCTAssertEqual(first.sourceRoom, "room-a")
        XCTAssertEqual(first.sessionId, "session-a")
        XCTAssertEqual(first.agent, "codex")
        XCTAssertEqual(first.model, "gpt-5")
        XCTAssertEqual(first.commandPreview, "npm test")
        XCTAssertEqual(first.deepLinkTarget,
                       CapabilityChatTarget(kind: "chat", roomId: "room-a", sessionId: "session-a"))

        store.record(
            .cli, name: "Bash", sessionId: nil, sourceId: "call-a", createdAt: now,
            toolName: "shell", commandPreview: "npm run test", durationMs: 250,
            outcome: .error, errorClass: "exit", sourceNamespace: "room-a"
        )
        XCTAssertEqual(store.events.count, 1)
        XCTAssertEqual(store.events[0].commandPreview, "npm run test")
        XCTAssertEqual(store.events[0].durationMs, 250)
        XCTAssertEqual(store.events[0].outcome, .error)
        XCTAssertEqual(store.events[0].sessionId, "session-a")
        XCTAssertEqual(store.events[0].resource?.cpuTimeMs, 24)

        let unchanged = store.events
        store.record(
            .cli, name: "Bash", sessionId: nil, sourceId: "call-a", createdAt: now,
            toolName: "shell", commandPreview: "npm run test", durationMs: 250,
            outcome: .error, errorClass: "exit", sourceNamespace: "room-a"
        )
        XCTAssertEqual(store.events, unchanged)
    }

    func testMergeUsesAuthenticatedRoomAndKeepsNewestBoundedMetadata() throws {
        let now = Date().timeIntervalSince1970 * 1_000 + 2_000
        let forged = CapabilityChatTarget(
            kind: "chat", roomId: "forged-room", sessionId: "session-a"
        )
        let initial = remoteEvent(
            sourceId: "remote-a", roomId: "forged-room", sessionId: "session-a",
            name: "github", createdAt: now, target: forged, outcome: .success
        )
        store.merge([initial], sourceNamespace: "room-a")
        let event = try XCTUnwrap(store.events.first)
        XCTAssertEqual(event.sourceRoom, "room-a")
        XCTAssertEqual(event.resource?.peakRssBytes, 112_000_000)
        XCTAssertEqual(event.deepLinkTarget,
                       CapabilityChatTarget(kind: "chat", roomId: "room-a", sessionId: "session-a"))

        let legacyUpdate = remoteEvent(
            sourceId: "remote-a", roomId: "room-a", sessionId: "session-a",
            name: "github", createdAt: now, target: nil, outcome: .success,
            resource: nil
        )
        store.merge([legacyUpdate], sourceNamespace: "room-a")
        XCTAssertEqual(store.events.first?.resource?.peakRssBytes, 112_000_000)

        let updated = remoteEvent(
            sourceId: "remote-a", roomId: "room-a", sessionId: "session-a",
            name: "github", createdAt: now, target: CapabilityChatTarget(
                kind: "chat", roomId: "room-a", sessionId: "session-a"
            ), outcome: .error
        )
        let second = remoteEvent(
            sourceId: "remote-b", roomId: nil, sessionId: nil,
            name: "documents", createdAt: now + 1, target: nil, outcome: .cancelled
        )
        store.merge([updated, second], sourceNamespace: "room-a")
        XCTAssertEqual(store.events.count, 2)
        XCTAssertEqual(store.events.first?.name, "documents")
        XCTAssertEqual(store.events.first(where: { $0.name == "github" })?.outcome, .error)

        let unchanged = store.events
        store.merge([updated, second], sourceNamespace: "room-a")
        XCTAssertEqual(store.events, unchanged)
    }

    func testPersistedHistoryDecodeMigratesTargetsSortsAndRejectsInvalidData() throws {
        XCTAssertTrue(CapabilityUsageStore.decodePersisted(Data("bad".utf8)).isEmpty)
        let now = Date().timeIntervalSince1970 * 1_000 + 10_000
        store.record(
            .mcp, name: "github", sessionId: "session", sourceId: "first",
            createdAt: now, commandPreview: "  npm   test  ", sourceNamespace: "room"
        )
        store.record(
            .skill, name: "documents", sessionId: nil, sourceId: "second",
            createdAt: now + 1
        )
        var snapshot = store.events
        snapshot[0].deepLinkTarget = CapabilityChatTarget(
            kind: "other", roomId: "forged", sessionId: "wrong"
        )
        snapshot[1].deepLinkTarget = CapabilityChatTarget(
            kind: "chat", roomId: "room", sessionId: "session"
        )
        let decoded = CapabilityUsageStore.decodePersisted(
            try JSONEncoder().encode(snapshot)
        )
        XCTAssertEqual(decoded.map(\.createdAt), [now + 1, now])
        XCTAssertNil(decoded[0].deepLinkTarget)
        XCTAssertEqual(decoded[1].commandPreview, "npm test")
        XCTAssertEqual(decoded[1].deepLinkTarget, CapabilityChatTarget(
            kind: "chat", roomId: "room", sessionId: "session"
        ))
    }

    private func remoteEvent(
        sourceId: String, roomId: String?, sessionId: String?, name: String,
        createdAt: Double, target: CapabilityChatTarget?, outcome: CapabilityOutcome,
        resource: CapabilityResourceUsage? = CapabilityResourceUsage(
            attribution: .attributed, cpuTimeMs: 24, peakRssBytes: 112_000_000
        )
    ) -> RemoteCapabilityUsageEvent {
        RemoteCapabilityUsageEvent(
            sourceId: sourceId, roomId: roomId, sessionId: sessionId,
            agent: "Claude Code", model: "claude-sonnet", kind: .mcp,
            name: name, toolName: "call", commandPreview: " run ",
            deepLinkTarget: target, createdAt: createdAt,
            estimatedContextTokens: 10, estimatedBaselineTokens: 30,
            durationMs: 50, outcome: outcome, errorClass: outcome == .error ? "remote" : nil,
            resource: resource
        )
    }
}
