import XCTest
@testable import GrantTap

final class ChildThreadTreeTests: XCTestCase {
    func testRowsEmitParentBeforeChildWithNormalizedDepthAndExcludeOrphans() {
        let rows = ChildThreadTree.rows(rootId: "root", threads: [
            thread("grandchild", parent: "child", depth: 99, startedAt: 30),
            thread("orphan", parent: "missing", depth: 1, startedAt: 40),
            thread("child", parent: "root", depth: 7, startedAt: 20),
        ])

        XCTAssertEqual(rows.map(\.thread.threadId), ["child", "grandchild"])
        XCTAssertEqual(rows.map(\.visualDepth), [1, 2])
        XCTAssertEqual(rows.map(\.thread.parentThreadId), ["root", "child"])
    }

    func testRowsExcludeCyclesWhileKeepingValidRootedBranches() {
        let rows = ChildThreadTree.rows(rootId: "root", threads: [
            thread("cycle-a", parent: "cycle-b", depth: 1, startedAt: 30),
            thread("valid", parent: "root", depth: 1, startedAt: 20),
            thread("cycle-b", parent: "cycle-a", depth: 2, startedAt: 40),
        ])

        XCTAssertEqual(rows.map(\.thread.threadId), ["valid"])
        XCTAssertEqual(rows.map(\.visualDepth), [1])
    }

    func testRowsOrderSiblingsByMostRecentActivityFirst() {
        let rows = ChildThreadTree.rows(rootId: "root", threads: [
            thread(
                "recently-active",
                parent: "root",
                depth: 1,
                startedAt: 10,
                lastActivityAt: 100
            ),
            thread(
                "newer-start",
                parent: "root",
                depth: 1,
                startedAt: 20,
                lastActivityAt: 50
            ),
        ])

        XCTAssertEqual(rows.map(\.thread.threadId), ["recently-active", "newer-start"])
    }

    func testActivityFallbackKeepsOnlyNewest32DistinctThreads() {
        let entries = (0..<40).map { index in
            ActivityEntry(
                id: "entry-\(index)",
                kind: "message",
                text: "event \(index)",
                createdAt: Double(index),
                childThreadId: "activity-\(index)",
                childThreadTitle: "Activity \(index)",
                childThreadDepth: 1
            )
        }

        let rows = ChildThreadTree.rows(rootId: "root", threads: [], activity: entries)

        XCTAssertEqual(rows.count, 32)
        XCTAssertEqual(Set(rows.map(\.thread.threadId)), Set((8..<40).map { "activity-\($0)" }))
    }

    func testMetadataPreventsActivityOnlyThreadsFromBypassingCatalogBound() {
        let catalogThread = thread("catalog-child", parent: "root", depth: 1, startedAt: 10)
        let activity = ActivityEntry(
            id: "entry",
            kind: "message",
            text: "legacy event",
            createdAt: 100,
            childThreadId: "activity-only",
            childThreadTitle: "Must not appear",
            childThreadDepth: 1
        )

        let rows = ChildThreadTree.rows(
            rootId: "root",
            threads: [catalogThread],
            activity: [activity]
        )

        XCTAssertEqual(rows.map(\.thread.threadId), ["catalog-child"])
    }

    func testActivityFallbackExcludesNestedThreadWithoutParentMetadata() {
        let direct = ActivityEntry(
            id: "direct-entry",
            kind: "message",
            text: "direct",
            createdAt: 10,
            childThreadId: "direct",
            childThreadTitle: "Direct",
            childThreadDepth: 1
        )
        let orphanedGrandchild = ActivityEntry(
            id: "nested-entry",
            kind: "message",
            text: "nested",
            createdAt: 20,
            childThreadId: "nested",
            childThreadTitle: "Nested",
            childThreadDepth: 2
        )

        let rows = ChildThreadTree.rows(
            rootId: "root",
            threads: [],
            activity: [direct, orphanedGrandchild]
        )

        XCTAssertEqual(rows.map(\.thread.threadId), ["direct"])
        XCTAssertEqual(rows.map(\.visualDepth), [1])
    }

    func testDisplayLabelPrefersAgentNameThenTitleThenCompactIdFallback() {
        let named = thread(
            "named-thread",
            parent: "root",
            depth: 1,
            title: "Title loses",
            agentName: "reviewer"
        )
        let titled = thread(
            "titled-thread",
            parent: "root",
            depth: 1,
            title: "Investigate tests"
        )
        let fallback = thread(
            "12345678-abcdef",
            parent: "root",
            depth: 1
        )

        XCTAssertEqual(ChildThreadDisplayRow(thread: named, visualDepth: 1).displayLabel, "reviewer")
        XCTAssertEqual(ChildThreadDisplayRow(thread: titled, visualDepth: 1).displayLabel, "Investigate tests")
        XCTAssertEqual(ChildThreadDisplayRow(thread: fallback, visualDepth: 1).displayLabel, "Agent 12345678")
    }

    func testFallbackUpdatesLatestTitleSaturatesTokensAndSortsStableTies() {
        let entries = [
            ActivityEntry(id: "old", kind: "tool", text: "Old", createdAt: 1,
                          estimatedContextTokens: Int.max, childThreadId: "same",
                          childThreadTitle: "Old title", childThreadDepth: 1),
            ActivityEntry(id: "new", kind: "tool", text: "New", createdAt: 2,
                          estimatedContextTokens: 50, childThreadId: "same",
                          childThreadTitle: "  Latest title  ", childThreadDepth: 1),
            ActivityEntry(id: "blank", kind: "tool", text: "Blank", createdAt: 2,
                          childThreadId: "alpha", childThreadTitle: "  ", childThreadDepth: 1),
            ActivityEntry(id: "ignored", kind: "tool", text: "Ignored", createdAt: 3,
                          childThreadId: "  ", childThreadDepth: 1),
        ]
        let rows = ChildThreadTree.rows(rootId: "root", threads: [], activity: entries)
        XCTAssertEqual(rows.map(\.thread.threadId), ["alpha", "same"])
        XCTAssertEqual(rows.last?.thread.title, "Latest title")
        XCTAssertEqual(rows.last?.thread.tokensSession, Int.max)

        let tied = ChildThreadTree.rows(rootId: "root", threads: [
            thread("b", parent: "root", depth: 1, startedAt: 2, lastActivityAt: 5),
            thread("a", parent: "root", depth: 1, startedAt: 2, lastActivityAt: 5),
            thread("new-start", parent: "root", depth: 1, startedAt: 3, lastActivityAt: 5),
        ])
        XCTAssertEqual(tied.map(\.thread.threadId), ["new-start", "a", "b"])
    }

    func testRowsHideCursorTaskToolClones() {
        let rows = ChildThreadTree.rows(rootId: "root", threads: [
            thread("listed-child", parent: "root", depth: 1, startedAt: 1),
            thread("task-3ef3af57-1111-4111-8111-1234567890ab", parent: "root", depth: 1, startedAt: 2),
        ])
        XCTAssertEqual(rows.map(\.thread.threadId), ["listed-child"])
    }

    private func thread(
        _ id: String,
        parent: String,
        depth: Int,
        startedAt: Double = 1,
        lastActivityAt: Double? = nil,
        title: String? = nil,
        agentName: String? = nil
    ) -> ChildThreadInfo {
        ChildThreadInfo(
            threadId: id,
            parentThreadId: parent,
            title: title,
            agentName: agentName,
            depth: depth,
            state: "idle",
            startedAt: startedAt,
            lastActivityAt: lastActivityAt ?? startedAt,
            tokensSession: 0,
            tokensLastTurn: 0
        )
    }
}
