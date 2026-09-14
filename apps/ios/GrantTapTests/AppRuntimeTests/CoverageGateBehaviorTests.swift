import Foundation
import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testProjectGroupingAttachmentGlyphsAndAuditClearCoverUserFacingVariants() {
        func session(_ cwd: String?) -> SessionInfo {
            SessionInfo(sessionId: UUID().uuidString, agent: "codex", cwd: cwd,
                        state: "idle", startedAt: 1, lastActivityAt: 2,
                        tokensSession: 0, tokensLastTurn: 0)
        }
        XCTAssertEqual(session("Users-alice-dev-granttap").projectGroupTitle, "granttap")
        XCTAssertEqual(session("/Users/alice/repo/").projectGroupKey, "proj:repo")
        for path in [nil, "repo", "project-slug", "/Users/alice", "/tmp", "/Desktop"] {
            XCTAssertEqual(session(path).projectGroupTitle, "No project")
        }
        XCTAssertGreaterThanOrEqual(session("/repo").idleFor, 0)

        XCTAssertEqual(AttachmentGlyph.forName("screen.JPEG"), "photo")
        XCTAssertEqual(AttachmentGlyph.forName("clip.mp4"), "video")
        XCTAssertEqual(AttachmentGlyph.forName("report.pdf"), "doc.richtext")
        XCTAssertEqual(AttachmentGlyph.forName("source.tar"), "doc.zipper")
        XCTAssertEqual(AttachmentGlyph.forName("notes.md"), "doc.text")
        XCTAssertEqual(AttachmentGlyph.forName("LICENSE"), "paperclip")

        let audit = AuditStore(loadPersisted: false)
        audit.record("coverage", detail: "Clear this entry")
        XCTAssertEqual(audit.events.count, 1)
        audit.clear()
        XCTAssertTrue(audit.events.isEmpty)
    }

    func testLegacyCatalogMigratesOnceToSQLite() throws {
        struct Legacy: Codable {
            let sessions: [SessionInfo]
            let history: [SessionInfo]
            let machine: String
            let tokensRecent: Int
            let tokenWindowHours: Int
            let generatedAt: Double
        }
        let storage = FileManager.default.temporaryDirectory
            .appendingPathComponent("granttap-legacy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storage) }
        let session = SessionInfo(
            sessionId: "legacy", agent: "claude", state: "idle",
            startedAt: 1, lastActivityAt: 2, tokensSession: 3, tokensLastTurn: 1
        )
        let legacy = Legacy(sessions: [session], history: [], machine: "Old Mac",
                            tokensRecent: 4, tokenWindowHours: 12, generatedAt: 5)
        try JSONEncoder().encode(legacy).write(
            to: storage.appendingPathComponent("sessions-catalog-cache.json")
        )

        let loaded = try XCTUnwrap(SessionCatalogCache.load(storageDirectory: storage))
        XCTAssertEqual(loaded.sessions.map(\.sessionId), ["legacy"])
        XCTAssertEqual(loaded.machine, "Old Mac")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: storage.appendingPathComponent("sessions-catalog-cache.json").path
        ))
    }

    func testTerminalRowAdmissionPreservesRequiredAndOnlyFitsOptionalRows() {
        let required = existingSessionDelivery(createdAt: 1, id: "required")
        var optional = existingSessionDelivery(createdAt: 2, id: "optional")
        optional.state = .failed
        let impossibleCount = DeliveryPersistence.appendingTerminalRows(
            required: [required], optional: [optional], maxCount: 0, maxEncodedBytes: 10_000
        )
        XCTAssertEqual(impossibleCount.map(\.id), ["required"])
        let impossibleBytes = DeliveryPersistence.appendingTerminalRows(
            required: [required], optional: [optional], maxCount: 2, maxEncodedBytes: 0
        )
        XCTAssertEqual(impossibleBytes.map(\.id), ["required"])
        let fitted = DeliveryPersistence.appendingTerminalRows(
            required: [], optional: [optional], maxCount: 1, maxEncodedBytes: 100_000
        )
        XCTAssertEqual(fitted.map(\.id), ["optional"])
        let skipped = DeliveryPersistence.appendingTerminalRows(
            required: [], optional: [optional], maxCount: 1, maxEncodedBytes: 2
        )
        XCTAssertTrue(skipped.isEmpty)
    }

    @MainActor
    func testTerminalEchoOfPhoneStubFailsFollowersWithoutAdoptingFakeNativeId() {
        let model = AppModel()
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            .empty, pairing: testPairing(room: "room-a")
        )
        let stub = "phone-stub"
        model.localOnlySessionIds = [stub]
        model.sessions = [stubSession(id: stub, at: 1)]
        model.deliveries = [existingSessionDelivery(
            createdAt: 1, id: "origin", sessionId: stub
        )]
        model.receive(AgentEvent(
            type: "agent.event", text: "Failed", requestId: nil, kind: "response",
            sessionId: stub, originMessageId: "origin", createdAt: 2
        ), fromRoom: "room-a")
        XCTAssertEqual(model.activities[stub]?.entries.last?.text, "Failed")
        XCTAssertEqual(model.resolvedSessionId(stub), stub)
    }

    @MainActor
    func testDebugDemoCaptureModesStaySideEffectFreeAndDeterministic() {
        let model = AppModel()
        setenv("GRANTTAP_CAPTURE_TASKS", "1", 1)
        model.startDemo()
        XCTAssertTrue(model.pending.isEmpty)
        XCTAssertTrue(model.questions.isEmpty)
        unsetenv("GRANTTAP_CAPTURE_TASKS")

        setenv("GRANTTAP_CHAT_SCREENSHOT", "1", 1)
        model.startDemo()
        XCTAssertEqual(model.deliveries.map(\.id), ["demo-photo-delivery"])
        XCTAssertTrue(model.pending.isEmpty)
        unsetenv("GRANTTAP_CHAT_SCREENSHOT")
        model.stopDemo()
    }
}
