import XCTest
@testable import GrantTap

final class ChatPinnedUserMessageTests: XCTestCase {
    private func entry(_ id: String, kind: String, at time: Double) -> ActivityEntry {
        ActivityEntry(id: id, kind: kind, text: id, createdAt: time)
    }

    func testPinnedMessageFollowsTheTranscriptWhenReadingEarlierTurns() {
        let rows = ChatActivityGrouping.rows([
            .activity(entry("first", kind: "user", at: 1)),
            .activity(entry("reply", kind: "assistant", at: 2)),
            .activity(entry("second", kind: "user", at: 3)),
            .activity(entry("answer", kind: "assistant", at: 4)),
        ])
        XCTAssertEqual(ChatPinnedUserMessage.entry(in: rows, topRowId: nil)?.id, "second")
        XCTAssertEqual(ChatPinnedUserMessage.entry(in: rows, topRowId: "activity:answer")?.id, "second")
        XCTAssertEqual(ChatPinnedUserMessage.entry(in: rows, topRowId: "activity:reply")?.id, "first")
    }

    func testFirstVisibleRowIgnoresRowsOutsideTheViewport() {
        let frames = [
            ChatRowPosition(id: "older", minY: -80, maxY: -1),
            ChatRowPosition(id: "reading", minY: -20, maxY: 40),
            ChatRowPosition(id: "next", minY: 45, maxY: 90),
            ChatRowPosition(id: "later", minY: 110, maxY: 180),
        ]
        XCTAssertEqual(ChatPinnedUserMessage.topVisibleRow(frames, viewportHeight: 100), "reading")
    }
}


extension ChatPinnedUserMessageTests {
    func testAttachmentOnlyRequestIsNavigable() {
        let attachment = ActivityEntry(id: "attachment", kind: "user", text: "", createdAt: 1,
            attachments: ["document.pdf"])
        let rows = ChatActivityGrouping.rows([.activity(attachment)])
        XCTAssertEqual(ChatPinnedUserMessage.entry(in: rows, topRowId: nil)?.id, "attachment")
    }
}
