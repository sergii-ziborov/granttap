import XCTest
@testable import GrantTap

final class TranscriptBackfillTests: XCTestCase {
    private func page(_ id: String, cursor: String?, requested: String?, more: Bool) -> SessionActivity {
        SessionActivity(sessionId: id, agent: "codex", state: "idle", entries: [], generatedAt: 1,
            history: .init(cursor: cursor, hasMore: more, requestedCursor: requested))
    }

    func testEveryActiveChatBackfillsFairlyWithoutOpeningIt() {
        var queue = TranscriptBackfill()
        let ids = Set((0..<100).map { "chat-\($0)" })
        var activities: [String: SessionActivity] = [:]
        var completed = Set<String>()
        for tick in 1...100 {
            let requests = queue.next(activeIds: ids, activities: activities, available: ids, now: Double(tick))
            XCTAssertLessThanOrEqual(requests.count, 2)
            for request in requests {
                let activity = page(request.sessionId, cursor: request.cursor == nil ? "older" : nil,
                    requested: request.cursor, more: request.cursor == nil)
                activities[request.sessionId] = activity
                queue.received(activity, now: Double(tick))
                if !activity.history!.hasMore { completed.insert(request.sessionId) }
            }
        }
        XCTAssertEqual(completed, ids)
        XCTAssertTrue(queue.next(activeIds: ids, activities: activities, available: ids, now: 1_000).isEmpty)
    }

    func testRestartResumesPersistedCursorAndOfflineDoesNotSchedule() {
        var queue = TranscriptBackfill()
        let saved = ["chat": page("chat", cursor: "oldest-saved", requested: "previous", more: true)]
        XCTAssertTrue(queue.next(activeIds: ["chat"], activities: saved, available: [], now: 1).isEmpty)
        let next = queue.next(activeIds: ["chat"], activities: saved, available: ["chat"], now: 2)
        XCTAssertEqual(next.first?.cursor, "oldest-saved")
        queue.received(page("chat", cursor: nil, requested: "unrelated", more: false), now: 3)
        XCTAssertEqual(queue.pending.count, 1)
        queue.failed(next[0], now: 4)
        XCTAssertTrue(queue.next(activeIds: ["chat"], activities: saved, available: ["chat"], now: 5).isEmpty)
        XCTAssertEqual(queue.next(activeIds: ["chat"], activities: saved, available: ["chat"], now: 30_005).count, 1)
    }

    func testTimeoutAndRepeatedCursorBackOffWithoutLooping() {
        var queue = TranscriptBackfill()
        let first = queue.next(activeIds: ["chat"], activities: [:], available: ["chat"], now: 1)[0]
        XCTAssertTrue(queue.next(activeIds: ["chat"], activities: [:], available: ["chat"], now: 20_001).isEmpty)
        let resumed = queue.next(activeIds: ["chat"], activities: [:], available: ["chat"], now: 50_002)
        XCTAssertEqual(resumed.count, 1)
        queue.failed(first, now: 50_003) // Late failure cannot remove the new request.
        XCTAssertEqual(queue.pending.count, 1)
        queue.received(page("chat", cursor: nil, requested: nil, more: true), now: 50_004)
        XCTAssertTrue(queue.next(activeIds: ["chat"], activities: [:], available: ["chat"], now: 50_005).isEmpty)
    }
    func testACompletedChatFetchesNewMessagesWhenItsCatalogChanges() throws {
        var queue = TranscriptBackfill()
        let completed = page("chat", cursor: nil, requested: nil, more: false)
        let cached = ["chat": completed]
        let head = try XCTUnwrap(queue.next(activeIds: ["chat"], activities: cached,
            available: ["chat"], versions: ["chat": 100], now: 1).first)
        XCTAssertNil(head.cursor, "Restart must verify the current head even with complete cached history")
        queue.received(completed, now: 2)
        XCTAssertTrue(queue.next(activeIds: ["chat"], activities: cached,
            available: ["chat"], versions: ["chat": 100], now: 3).isEmpty)
        let changed = try XCTUnwrap(queue.next(activeIds: ["chat"], activities: cached,
            available: ["chat"], versions: ["chat": 200], now: 4).first)
        XCTAssertNil(changed.cursor)
        queue.received(completed, now: 5)
        XCTAssertTrue(queue.next(activeIds: ["chat"], activities: cached,
            available: ["chat"], versions: ["chat": 200], now: 6).isEmpty)
    }

    func testActiveUpdatesDoNotStarveOlderPagesAndRetryAnUnansweredHead() throws {
        var queue = TranscriptBackfill()
        _ = queue.next(activeIds: ["chat"], activities: [:], available: ["chat"],
                       versions: ["chat": 100], now: 1)
        let older = page("chat", cursor: "older", requested: nil, more: true)
        queue.received(older, now: 2)
        let tail = try XCTUnwrap(queue.next(activeIds: ["chat"], activities: ["chat": older],
            available: ["chat"], versions: ["chat": 200], now: 3).first)
        XCTAssertEqual(tail.cursor, "older", "Finish older history before chasing the next live revision")
        let complete = page("chat", cursor: nil, requested: "older", more: false)
        queue.received(complete, now: 4)
        let head = try XCTUnwrap(queue.next(activeIds: ["chat"], activities: ["chat": complete],
            available: ["chat"], versions: ["chat": 200], now: 5).first)
        XCTAssertNil(head.cursor)
        XCTAssertTrue(queue.next(activeIds: ["chat"], activities: ["chat": complete],
            available: ["chat"], versions: ["chat": 200], now: 20_005).isEmpty)
        XCTAssertNil(try XCTUnwrap(queue.next(activeIds: ["chat"], activities: ["chat": complete],
            available: ["chat"], versions: ["chat": 200], now: 50_006).first).cursor)
    }

    func testNowRefreshesLatestMessagesBeforeItsLongHistoryFinishes() throws {
        var queue = TranscriptBackfill()
        _ = queue.next(activeIds: ["chat"], activities: [:], available: ["chat"],
                       versions: ["chat": 100], now: 1)
        let saved = page("chat", cursor: "saved-oldest", requested: nil, more: true)
        queue.received(saved, now: 2)
        let refreshed = try XCTUnwrap(queue.next(activeIds: ["chat"], activities: ["chat": saved],
            available: ["chat"], versions: ["chat": 200], now: 30_002).first)
        XCTAssertNil(refreshed.cursor, "New messages must not wait for the complete transcript")
        queue.received(page("chat", cursor: "recent", requested: nil, more: true), now: 30_003)
        let resumed = try XCTUnwrap(queue.next(activeIds: ["chat"], activities: ["chat": saved],
            available: ["chat"], versions: ["chat": 200], now: 30_004).first)
        XCTAssertEqual(resumed.cursor, "saved-oldest", "Refreshing Now must retain the older paging position")
    }

    func testUnopenedNowHeadsTakePriorityOverOlderHistoryPages() {
        var queue = TranscriptBackfill()
        queue.concurrency = 1
        _ = queue.next(activeIds: ["a"], activities: [:], available: ["a"],
                       versions: ["a": 100], now: 1)
        let saved = page("a", cursor: "older", requested: nil, more: true)
        queue.received(saved, now: 2)
        let next = queue.next(activeIds: ["a", "z"], activities: ["a": saved],
            available: ["a", "z"], versions: ["a": 100, "z": 200], now: 3)
        XCTAssertEqual(next.first?.sessionId, "z")
        XCTAssertNil(next.first?.cursor)
    }

    func testChangedNowHeadWinsEvenWhenAnotherHistoryPageWasServedLessRecently() {
        var queue = TranscriptBackfill()
        queue.concurrency = 1
        _ = queue.next(activeIds: ["a"], activities: [:], available: ["a"], versions: ["a": 100], now: 1)
        let older = page("a", cursor: "older", requested: nil, more: true)
        queue.received(older, now: 2)
        _ = queue.next(activeIds: ["a", "z"], activities: ["a": older], available: ["z"],
                       versions: ["a": 100, "z": 200], now: 3)
        let complete = page("z", cursor: nil, requested: nil, more: false)
        queue.received(complete, now: 4)
        let next = queue.next(activeIds: ["a", "z"], activities: ["a": older, "z": complete],
            available: ["a", "z"], versions: ["a": 100, "z": 300], now: 5)
        XCTAssertEqual(next.first?.sessionId, "z")
        XCTAssertNil(next.first?.cursor)
    }

}
