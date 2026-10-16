import XCTest
@testable import GrantTap

final class TranscriptRequestNavigationTests: XCTestCase {
    func testPreparedRequestsKeepFragmentPagingAndPreviousRequestSemantics() {
        let entries = requestsAndReplies()
        let index = TranscriptRequestIndex(entries)
        for id in entries.map(\.id) + ["missing"] {
            XCTAssertEqual(index.previous(before: id), TranscriptRequestBoundary.previous(in: entries, before: id))
            XCTAssertEqual(index.request(containing: id),
                           TranscriptRequestBoundary.request(containing: id, in: entries))
            XCTAssertEqual(index.needsEarlierPage(before: id),
                           TranscriptRequestBoundary.needsEarlierPage(in: entries, before: id))
        }
        XCTAssertEqual(index.previous(before: nil), TranscriptRequestBoundary.previous(in: entries, before: nil))
        XCTAssertEqual(index.needsEarlierPage(before: nil),
                       TranscriptRequestBoundary.needsEarlierPage(in: entries, before: nil))
        XCTAssertNil(TranscriptRequestIndex([]).previous(before: nil))
        XCTAssertTrue(TranscriptRequestIndex([]).needsEarlierPage(before: nil))
    }

    func testPreparedNavigationFollowsGroupedCallsAndAttachmentFragments() {
        let rows = ChatActivityGrouping.rows(requestsAndReplies().map(CombinedTaskTimelineItem.activity))
        let navigation = ChatRequestNavigation(rows: rows)
        for id in rows.map(\.id) + ["missing"] {
            XCTAssertEqual(navigation.entry(topRowId: id), ChatPinnedUserMessage.entry(in: rows, topRowId: id))
            for anchor in ["text", "image-only", "child", "missing"] {
                XCTAssertEqual(navigation.navigationEntry(topRowId: id, afterJump: anchor),
                    ChatPinnedUserMessage.navigationEntry(in: rows, topRowId: id, afterJump: anchor))
            }
        }
        XCTAssertEqual(navigation.entry(topRowId: nil), ChatPinnedUserMessage.entry(in: rows, topRowId: nil))
        XCTAssertEqual(navigation.request(atRow: "activity:file")?.id, "text")
        XCTAssertNil(navigation.request(atRow: "activity:answer"))
        XCTAssertNil(ChatRequestNavigation(rows: []).entry(topRowId: nil))
    }

    private func requestsAndReplies() -> [ActivityEntry] {
        [
            .init(id: "older-answer", kind: "message", text: "Earlier page", createdAt: 0),
            .init(id: "image", kind: "user", text: "", createdAt: 1, attachments: ["image.jpg"]),
            .init(id: "text", kind: "user", text: "Question", createdAt: 1),
            .init(id: "file", kind: "user", text: "", createdAt: 1, attachments: ["file.pdf"]),
            .init(id: "answer", kind: "message", text: "Reply", createdAt: 2),
            .init(id: "tool-1", kind: "tool", text: "Read", createdAt: 3),
            .init(id: "tool-2", kind: "tool", text: "Search", createdAt: 4),
            .init(id: "second", kind: "user", text: "Next question", createdAt: 5),
            .init(id: "third", kind: "user", text: "Distinct same-time question", createdAt: 5),
            .init(id: "child", kind: "user", text: "Nested", createdAt: 5, childThreadId: "nested"),
            .init(id: "blank", kind: "user", text: "  ", createdAt: 6),
            .init(id: "image-only", kind: "user", text: "", createdAt: 7, attachments: ["another.jpg"]),
            .init(id: "last", kind: "message", text: "Reply", createdAt: 8),
        ]
    }
}
