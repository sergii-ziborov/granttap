import XCTest
@testable import GrantTap

final class TranscriptCacheTests: XCTestCase {
    func testColdOpeningBuildsOneProjectionAndRetainsAllSavedMessages() {
        let cache = ChatTranscriptCache()
        let entries = DemoLongTranscript.activity(sessionId: "long", at: 10_000).entries
        var builds = 0
        let build: ([CombinedTaskTimelineItem]) -> ChatTranscriptPresentation = { _ in
            builds += 1
            return ChatTranscriptPresentation(items: entries.map(CombinedTaskTimelineItem.activity), entries: entries)
        }
        let first = cache.value(sessionId: "long", revision: revision(), build: build)
        let next = cache.value(sessionId: "long", revision: revision(), build: build)
        XCTAssertEqual(builds, 1, "The opening layout must prepare a large transcript only once.")
        XCTAssertEqual(first.rows.count, 5_000)
        XCTAssertEqual(next.rows.last?.id, "activity:long-4999")
    }

    func testOwnRevisionRebuildsAndOnlyTheSameConversationRetainsHistory() {
        let cache = ChatTranscriptCache()
        let entry = ActivityEntry(id: "saved", kind: "message", text: "Saved response", createdAt: 1)
        _ = cache.value(sessionId: "one", revision: revision()) { _ in
            ChatTranscriptPresentation(items: [.activity(entry)], entries: [entry])
        }
        let retained = cache.value(sessionId: "one", revision: revision(activity: 2)) { history in
            ChatTranscriptPresentation(items: history, entries: [])
        }
        XCTAssertEqual(retained.rows.first?.id, "activity:saved")
        let other = cache.value(sessionId: "two", revision: revision(activity: 2)) { history in
            ChatTranscriptPresentation(items: history, entries: [])
        }
        XCTAssertTrue(other.items.isEmpty, "Saved messages must not leak to another conversation.")
        _ = cache.value(sessionId: "two", revision: revision()) { _ in
            ChatTranscriptPresentation(items: [.activity(entry)], entries: [entry])
        }
        let room = cache.value(sessionId: "two", revision: revision(room: "another")) { history in
            ChatTranscriptPresentation(items: history, entries: [])
        }
        XCTAssertTrue(room.items.isEmpty, "Changing accounts/rooms must clear the retained projection.")
    }

    private func revision(activity: UInt64 = 1, room: String = "room") -> ChatTranscriptRevision {
        ChatTranscriptRevision(meshEvents: [], executions: ["long"],
                               activityRevisions: [activity], threads: [], roomId: room)
    }
}
