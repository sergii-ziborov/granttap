import XCTest
@testable import GrantTap

final class TranscriptArchiveTests: XCTestCase {
    func testMacArchiveRetainsAllPagesAndCursorsUntilCleared() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let archive = TranscriptArchive(directory: directory)
        defer { try? archive.clear() }
        XCTAssertTrue(archive.load().isEmpty)
        XCTAssertEqual(archive.bytes, 0)
        let entries = (0..<900).map {
            ActivityEntry(id: "entry-\($0)", kind: "message", text: "Reply", createdAt: Double($0))
        }
        let activity = SessionActivity(sessionId: "../chat", agent: "codex", state: "idle",
            entries: entries, generatedAt: 900, history: .init(cursor: "native", hasMore: true))
        try archive.save(activity)
        try archive.save(activity)
        XCTAssertEqual(archive.load()[activity.sessionId], activity)
        XCTAssertGreaterThan(archive.bytes, 0)
        let file = directory.appendingPathComponent("invalid.json")
        try Data("invalid".utf8).write(to: file)
        try JSONEncoder().encode(activity).write(to: directory.appendingPathComponent("wrong-id.json"))
        XCTAssertEqual(archive.load().count, 1)
        try archive.clear()
        try archive.clear()
        XCTAssertTrue(archive.load().isEmpty)
        XCTAssertEqual(archive.bytes, 0)
    }

    func testRequestBoundariesExcludeAgentChildrenAndNavigateAttachmentRequests() {
        let first = ActivityEntry(id: "first", kind: "user", text: "", createdAt: 0, attachments: ["file.pdf"])
        let second = ActivityEntry(id: "second", kind: "user", text: "Request", createdAt: 1)
        let child = ActivityEntry(id: "child", kind: "user", text: "Child", createdAt: 2, childThreadId: "agent")
        let rows = [first, second, child]
        XCTAssertEqual(TranscriptRequestBoundary.previous(in: rows, before: nil)?.id, "second")
        XCTAssertEqual(TranscriptRequestBoundary.previous(in: rows, before: "second")?.id, "first")
        XCTAssertNil(TranscriptRequestBoundary.previous(in: rows, before: "first"))
        XCTAssertFalse(TranscriptRequestBoundary.needsEarlierPage(in: rows, before: nil))
        XCTAssertTrue(TranscriptRequestBoundary.needsEarlierPage(in: [second, child], before: nil))
        XCTAssertFalse(TranscriptRequestBoundary.needsEarlierPage(in: rows, before: "second"))
        XCTAssertTrue(TranscriptRequestBoundary.needsEarlierPage(in: rows, before: "first"))
        XCTAssertEqual(TranscriptRequestBoundary.retainedEntries(rows, limit: 1), rows)
        XCTAssertEqual(TranscriptRequestBoundary.retainedEntries([], limit: 300), [])
    }
}
