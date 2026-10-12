import XCTest
@testable import GrantTap

final class ProviderContextTests: XCTestCase {
    private let context = "<external_codex_apps_open_page>{\"page_id\":null}</external_codex_apps_open_page>"

    private func entry(_ text: String, id: String = "native", kind: String = "user",
                       attachments: [String]? = nil) -> ActivityEntry {
        ActivityEntry(id: id, kind: kind, text: text, createdAt: 1, attachments: attachments)
    }

    private func activity(_ entries: [ActivityEntry], agent: String = "codex") -> SessionActivity {
        SessionActivity(sessionId: "context-chat", agent: agent, state: "idle",
                        entries: entries, generatedAt: 1)
    }

    @MainActor
    func testLiveAndMergedCodexActivityExcludesHostContext() {
        let incoming = activity([entry(context), entry(context + "\nReview this task", id: "request")])
        XCTAssertEqual(incoming.entries.map(\.text), ["Review this task"])
        let merged = AppModel.mergeActivity(existing: activity([entry("Earlier request", id: "earlier")]),
                                            incoming: incoming)
        XCTAssertEqual(merged.entries.map(\.text), ["Earlier request", "Review this task"])
    }

    func testLegacyDiskArchiveFiltersContextWithoutClearingTheChat() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let archive = TranscriptArchive(directory: directory)
        defer { try? archive.clear() }
        let saved = activity([entry("Real request")])
        try archive.save(saved)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory,
                                                                        includingPropertiesForKeys: nil).first)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(saved))
                                    as? [String: Any])
        let rows = [entry(context), entry(context + "\nReal request", id: "request"),
                    entry(context, id: "photo", attachments: ["diagram.png"])]
        legacy["entries"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rows))
        try JSONSerialization.data(withJSONObject: legacy).write(to: file)
        let restored = try XCTUnwrap(archive.load()[saved.sessionId])
        XCTAssertEqual(restored.entries.map(\.id), ["request", "photo"])
        XCTAssertEqual(restored.entries.map(\.text), ["Real request", ""])
        XCTAssertEqual(restored.entries.last?.attachments, ["diagram.png"])
        XCTAssertEqual(restored.sessionId, saved.sessionId)
        XCTAssertGreaterThan(archive.bytes, 0)
    }

    func testOrdinaryJSONQuotedMarkupAndLocalUserMessagesRemainIntact() {
        let rows = [entry("{\"page_id\":null}"), entry("Explain this: " + context, id: "quote"),
                    entry(context, id: "tool", kind: "tool"), entry(context, id: "local-user-123")]
        XCTAssertEqual(activity(rows).entries, rows)
        XCTAssertEqual(activity([entry(context)], agent: "claude").entries, [entry(context)])
    }

    func testRepeatedAndIncompleteMetadataNeverBecomesAnOfflineRequest() throws {
        // Encode raw entries separately to reproduce an archive written before the fix.
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(activity([])))
                                    as? [String: Any])
        let rows = [entry("<external_codex_apps_open_page>{\"page_id\":null}"),
                    entry(context + "\n" + context + "\nContinue", id: "continue")]
        payload["entries"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rows))
        let restored = try JSONDecoder().decode(SessionActivity.self,
                            from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertEqual(restored.entries.map(\.text), ["Continue"])
        XCTAssertEqual(TranscriptRequestBoundary.previous(in: restored.entries, before: nil)?.id, "continue")
    }
}
