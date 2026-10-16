import XCTest
@testable import GrantTap

@MainActor
final class LongTranscriptMergeTests: XCTestCase {
    func testLargeNativePageKeepsHistoryAndMigratesOnlyActualLegacyAliases() {
        let count = 20_000
        let entries = (0..<count).map { index in
            ActivityEntry(id: "s:\(index):0123456789abcdef:0", kind: "message",
                          text: "Recorded line \(index)", createdAt: Double(index))
        }
        let old = ActivityEntry(id: "s:20001:100", kind: "message", text: "Migrated line", createdAt: 20_001)
        let native = ActivityEntry(id: "s:20001:fedcba9876543210:0", kind: "final",
                                   text: old.text, createdAt: old.createdAt)
        let existing = SessionActivity(sessionId: "s", agent: "codex", state: "idle",
                                        entries: entries + [old], generatedAt: 20_002)
        let page = SessionActivity(sessionId: "s", agent: "codex", state: "idle",
            entries: Array(entries.suffix(1_000)) + [native], generatedAt: 20_003,
            history: .init(hasMore: false, requestedCursor: "older"))
        let start = Date()
        let merged = AppModel.mergeActivity(existing: existing, incoming: page)
        print("TRANSCRIPT_MERGE_WITNESS retained=\(count) page=1001 seconds=\(Date().timeIntervalSince(start))")
        XCTAssertEqual(merged.entries.count, count + 1)
        XCTAssertEqual(merged.entries.first, entries.first)
        XCTAssertEqual(merged.entries.last, native)
        XCTAssertFalse(merged.entries.contains { $0.id == old.id })
        XCTAssertEqual(AppModel.mergeActivity(existing: merged, incoming: page).entries, merged.entries)
    }
}
