import XCTest
@testable import GrantTap

final class ChatReplyChangesTests: XCTestCase {
    func testCurrentReplyExcludesEarlierRepliesAndDoesNotCountReportedSummaryTwice() {
        let old = RecordedFileChange(path: "old.swift", linesAdded: 99, linesRemoved: 99, diff: "+old")
        let new = RecordedFileChange(path: "new.swift", linesAdded: 4, linesRemoved: 2, diff: "+new")
        let entries = [
            ActivityEntry(id: "old-user", kind: "user", text: "Previous", createdAt: 1),
            ActivityEntry(id: "old-final", kind: "final", text: "Previous result", createdAt: 2,
                          fileChanges: [old]),
            ActivityEntry(id: "new-user", kind: "user", text: "Current", createdAt: 3),
            ActivityEntry(id: "edit", kind: "tool", text: "Saved", createdAt: 4, fileChanges: [new]),
            ActivityEntry(id: "final", kind: "final", text: "Done", createdAt: 5, fileChanges: [new]),
        ]
        XCTAssertEqual(ChatFileChanges.currentReply(entries: entries), [new])
        XCTAssertEqual(ChatFileChanges.currentReply(entries: Array(entries.dropLast())), [new])
        XCTAssertEqual(ChatFileChanges.currentReply(entries: []), [])
    }

    func testWorkingReplyCombinesSuccessfulRecordedEditsInEachFile() {
        let first = RecordedFileChange(path: "same.swift", linesAdded: 2, linesRemoved: 1, diff: "+first")
        let next = RecordedFileChange(path: first.path, linesAdded: 3, linesRemoved: 2,
                                      diff: "+next", diffTruncated: true)
        let entries = [
            ActivityEntry(id: "user", kind: "user", text: "Current", createdAt: 1),
            ActivityEntry(id: "first", kind: "tool", text: "Saved", createdAt: 2, fileChanges: [first]),
            ActivityEntry(id: "next", kind: "tool", text: "Saved", createdAt: 3, fileChanges: [next]),
        ]
        let file = ChatFileChanges.currentReply(entries: entries).first
        XCTAssertEqual(file?.linesAdded, 5)
        XCTAssertEqual(file?.linesRemoved, 3)
        XCTAssertEqual(file?.diff, "+first\n+next")
        XCTAssertEqual(file?.diffTruncated, true)
    }
}
