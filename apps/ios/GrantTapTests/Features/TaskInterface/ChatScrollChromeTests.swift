import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class ChatScrollChromeTests: XCTestCase {
    private func user(_ id: String, text: String, at: Double) -> CombinedTaskTimelineItem {
        .activity(ActivityEntry(id: id, kind: "user", text: text, createdAt: at))
    }

    private func agent(_ id: String, at: Double) -> CombinedTaskTimelineItem {
        .activity(ActivityEntry(id: id, kind: "message", text: "ok", createdAt: at))
    }

    func testUserLinesStripHostMarksAndNameAnEmptyPhoto() {
        let lines = ChatScrollChrome.userLines([
            user("a", text: "<timestamp>1</timestamp><user_query>\nShip it", at: 1),
            agent("b", at: 2),
            user("c", text: "   ", at: 3),
        ])
        XCTAssertEqual(lines.map(\.entryId), ["a", "c"])
        XCTAssertEqual(lines.map(\.scrollId), ["activity:a", "activity:c"])
        XCTAssertEqual(lines[0].text, "Ship it")
        XCTAssertEqual(lines[1].text, L("Attachment"))
    }

    func testPinnedIsTheNewestUserLineThatHasCrossedTheTop() {
        let items = [
            user("one", text: "first", at: 1),
            agent("reply", at: 2),
            user("two", text: "second", at: 3),
        ]
        let users = ChatScrollChrome.userLines(items)
        let ordered = items.map(\.id)
        XCTAssertNil(ChatScrollChrome.pinned(
            users: users,
            minYById: ["activity:one": 80, "activity:two": 400],
            visibleIds: ["activity:one", "activity:two"],
            orderedIds: ordered,
            top: 36
        ))
        XCTAssertEqual(ChatScrollChrome.pinned(
            users: users,
            minYById: ["activity:one": -10, "activity:two": 120],
            visibleIds: ["activity:two"],
            orderedIds: ordered,
            top: 36
        )?.entryId, "one")
        XCTAssertEqual(ChatScrollChrome.pinned(
            users: users,
            minYById: ["activity:two": 8],
            visibleIds: ["activity:two"],
            orderedIds: ordered,
            top: 36
        )?.entryId, "two")
        XCTAssertEqual(ChatScrollChrome.pinned(
            users: users,
            minYById: [:],
            visibleIds: ["activity:reply"],
            orderedIds: ordered,
            top: 36
        )?.entryId, "one")
    }

    func testJumpToLatestAppearsOnlyAfterTheFootLeavesTheScreen() {
        XCTAssertFalse(ChatScrollChrome.showJumpToLatest(lastMaxY: 300, viewportHeight: 300))
        XCTAssertFalse(ChatScrollChrome.showJumpToLatest(lastMaxY: nil, viewportHeight: 300))
        XCTAssertTrue(ChatScrollChrome.showJumpToLatest(lastMaxY: 420, viewportHeight: 300))
    }

    func testStickyBarAndJumpButtonRender() {
        RenderProbe.render(ChatStickyUserBar(text: "Ship the ten photos…", accent: Theme.claude, action: {}))
        RenderProbe.render(ChatJumpToLatestButton(action: {}))
    }
}
