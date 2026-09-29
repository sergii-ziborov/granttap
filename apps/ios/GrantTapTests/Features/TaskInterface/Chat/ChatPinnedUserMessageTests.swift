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
    func testAttachmentFragmentsKeepTheirRequestTextAndDoNotBecomePreviousRequests() {
        let older = entry("older", kind: "user", at: 1)
        let text = entry("question", kind: "user", at: 2)
        let image = ActivityEntry(id: "image", kind: "user", text: "", createdAt: 2, attachments: ["Image"])
        let document = ActivityEntry(id: "file", kind: "user", text: "", createdAt: 2, attachments: ["file.pdf"])
        let answer = entry("answer", kind: "assistant", at: 3)
        let entries = [older, text, image, document, answer]
        let rows = ChatActivityGrouping.rows(entries.map { .activity($0) })
        XCTAssertEqual(ChatPinnedUserMessage.entry(in: rows, topRowId: nil)?.id, text.id)
        XCTAssertEqual(ChatPinnedUserMessage.entry(in: rows, topRowId: "activity:file")?.id, text.id)
        XCTAssertEqual(TranscriptRequestBoundary.previous(in: entries, before: nil)?.id, text.id)
        XCTAssertEqual(TranscriptRequestBoundary.previous(in: entries, before: image.id)?.id, older.id)
        XCTAssertTrue(TranscriptRequestBoundary.needsEarlierPage(in: [text, image, document], before: nil))
        XCTAssertEqual(TranscriptRequestBoundary.retainedEntries(entries, limit: 1), entries)
    }

    func testRequestAboveReadingPositionWinsOverLatestRequestAndOldJumpAnchor() {
        let rows = ChatActivityGrouping.rows([
            .activity(entry("first", kind: "user", at: 1)),
            .activity(entry("first-answer", kind: "assistant", at: 2)),
            .activity(entry("second", kind: "user", at: 3)),
            .activity(entry("second-answer", kind: "assistant", at: 4)),
            .activity(entry("latest", kind: "user", at: 5)),
        ])
        XCTAssertEqual(ChatPinnedUserMessage.navigationEntry(in: rows,
            topRowId: "activity:first-answer", afterJump: "second")?.id, "first")
        XCTAssertEqual(ChatPinnedUserMessage.navigationEntry(in: rows,
            topRowId: "activity:second-answer", afterJump: nil)?.id, "second")
        XCTAssertEqual(ChatPinnedUserMessage.navigationEntry(in: rows,
            topRowId: "activity:second", afterJump: "second")?.id, "first")
        XCTAssertNil(ChatPinnedUserMessage.navigationEntry(in: rows,
            topRowId: "activity:first", afterJump: "first"))
    }

    func testReadingBeforeTheFirstLoadedRequestNeverJumpsDownToIt() {
        let rows = ChatActivityGrouping.rows([
            .activity(entry("older-answer", kind: "assistant", at: 1)),
            .activity(entry("newer-request", kind: "user", at: 2)),
        ])
        XCTAssertNil(ChatPinnedUserMessage.entry(in: rows, topRowId: "activity:older-answer"))
    }

    func testAttachmentOnlyRequestIsNavigable() {
        let attachment = ActivityEntry(id: "attachment", kind: "user", text: "", createdAt: 1,
            attachments: ["document.pdf"])
        let rows = ChatActivityGrouping.rows([.activity(attachment)])
        XCTAssertEqual(ChatPinnedUserMessage.entry(in: rows, topRowId: nil)?.id, "attachment")
    }
}
