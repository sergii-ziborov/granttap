import XCTest
@testable import GrantTap

@MainActor
final class SubmittedDocumentReplicaTests: XCTestCase {
    func testSubmittedNamesKeepTheirMessageOrderWhenCachedDocumentsAreMerged() throws {
        let model = AppModel()
        model.demoMode = true
        model.connectionRegistry = .empty
        model.sessionSourceRooms = [:]
        let session = UUID().uuidString
        let entry = ActivityEntry(id: "ordered-files", kind: "user", text: "Files", createdAt: 1,
                                  attachments: ["Z.md", "A.md"])
        model.activities = [session: .init(sessionId: session, agent: "codex", state: "idle",
                                           entries: [entry], generatedAt: 1)]
        defer { ReplicaImageStore.shared.clear() }
        try ReplicaDocumentStore.shared.save(["A.md", "X.md"].map {
            .init(name: $0, mimeType: "text/markdown", data: Data("# Sample".utf8))
        }, scope: "local-mac", sessionId: session, entryId: entry.id)
        XCTAssertEqual(model.documentNames(for: entry, sessionId: session), ["Z.md", "A.md", "X.md"])
    }

    func testImageLookupKeepsTheActualExecutionAndUsesExplicitScopeOnlyForMirrors() {
        let model = AppModel()
        model.demoMode = true
        let picture = ActivityEntry(id: "older-picture", kind: "user", text: "", createdAt: 1,
                                    attachments: ["Image"])
        model.activities = ["older": .init(sessionId: "older", agent: "codex", state: "idle",
            entries: [picture], generatedAt: 1), "current": .init(sessionId: "current", agent: "codex", state: "idle",
            entries: [], generatedAt: 2)]
        XCTAssertEqual(model.imageConversation(forEntryId: picture.id, preferredSessionId: "current"), "older")
        model.activities["current"] = .init(sessionId: "current", agent: "codex", state: "idle",
                                             entries: [picture], generatedAt: 2)
        XCTAssertNil(model.imageConversation(forEntryId: picture.id))
        XCTAssertEqual(model.imageConversation(forEntryId: picture.id, preferredSessionId: "current"), "current")
    }

    func testNewTaskKeepsMarkdownAfterNativeSessionRemapAndOutboxRemoval() throws {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        model.demoMode = true
        model.deliveries = []
        model.activities = [:]
        model.connectionRegistry = .empty
        model.sessionSourceRooms = [:]
        let oldId = UUID().uuidString, nativeId = UUID().uuidString
        let session = SessionInfo(sessionId: oldId, agent: "codex", state: "working",
            startedAt: now, lastActivityAt: now, tokensSession: 0, tokensLastTurn: 0)
        model.sessions = [session]
        model.localOnlySessionIds = []
        let file = try XCTUnwrap(MarkdownPaste.attachment(for: "# New Task document"))
        model.queueChatMessage("Read this", to: session, attachments: [file.payload])
        let id = try XCTUnwrap(model.deliveries.first?.id)
        model.sendChatQueuedMessageNow(id)
        model.remapLocalSession(from: oldId, to: nativeId)
        model.deliveries = []
        XCTAssertEqual(model.sentAttachment(forEntryId: "local-user-\(id)", name: file.name)?.data, file.data)
    }

    func testPastedMarkdownPreviewSurvivesOutboxCleanupAndNativeEcho() throws {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        model.demoMode = true
        model.deliveries = []
        model.activities = [:]
        model.localOnlySessionIds = []
        model.sessionSourceRooms = [:]
        model.connectionRegistry = .empty
        let session = SessionInfo(sessionId: UUID().uuidString, agent: "codex", state: "working",
            startedAt: now, lastActivityAt: now, tokensSession: 0, tokensLastTurn: 0)
        model.sessions = [session]
        let draft = try XCTUnwrap(MarkdownPaste.attachment(for: "# Full document\n\n- First\n- Second"))
        model.queueChatMessage("Read this document", to: session, attachments: [draft.payload])
        let id = try XCTUnwrap(model.deliveries.first?.id)
        model.sendChatQueuedMessageNow(id)
        model.applyActivity(.init(sessionId: session.sessionId, agent: "codex", state: "working",
            entries: [.init(id: "native-document", kind: "user", text: "Read this document", createdAt: now)],
            generatedAt: now))
        model.deliveries = []
        let restored = try XCTUnwrap(model.sentAttachment(forEntryId: "native-document", name: draft.name))
        XCTAssertEqual(try AttachmentPreviewFile(restored).text, String(data: draft.data, encoding: .utf8))
        let original = try XCTUnwrap(model.sentAttachment(forEntryId: "local-user-\(id)", name: draft.name,
                                                         sessionId: session.sessionId))
        XCTAssertEqual(original.data, draft.data)
    }
}
