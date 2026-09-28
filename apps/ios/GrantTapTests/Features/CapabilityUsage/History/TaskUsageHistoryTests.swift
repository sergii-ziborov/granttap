import SwiftUI
import UIKit
import XCTest
@testable import GrantTap

/// A task's own spending, which the global Usage numbers cannot answer.
final class TaskUsageHistoryTests: XCTestCase {
    private func event(
        _ name: String, session: String?, kind: CapabilityUsageKind = .mcp,
        createdAt: Double = 1_000, outcome: CapabilityOutcome = .success,
        cpuMs: Int? = nil, peak: Int? = nil
    ) -> CapabilityUsageEvent {
        CapabilityUsageEvent(
            id: "\(name)-\(createdAt)", sourceId: "room:\(name)-\(createdAt)",
            kind: kind, name: name, sessionId: session, createdAt: createdAt,
            toolName: name, outcome: outcome,
            resource: cpuMs == nil && peak == nil ? nil : CapabilityResourceUsage(
                attribution: .attributed, cpuTimeMs: cpuMs, peakRssBytes: peak
            )
        )
    }

    func testOnlyThisTasksCallsAreCounted() {
        let all = [
            event("github", session: "task-a"),
            event("bash", session: "task-b", kind: .cli),
            event("review", session: nil, kind: .skill),
        ]
        let mine = TaskUsageHistory.events(all, sessionIds: ["task-a"])
        XCTAssertEqual(mine.map(\.name), ["github"])
        // A call belonging to no task is nobody's, not everybody's.
        XCTAssertEqual(TaskUsageHistory.events(all, sessionIds: []).count, 0)
    }

    func testATaskIsFoundUnderEveryIdItHasWornd() {
        // A task keeps its identity across provider changes; its session id
        // does not, so both must resolve to the same history.
        let all = [
            event("github", session: "old-id"),
            event("bash", session: "new-id", kind: .cli),
        ]
        let mine = TaskUsageHistory.events(all, sessionIds: ["old-id", "new-id"])
        XCTAssertEqual(Set(mine.map(\.name)), ["github", "bash"])
    }

    func testCallsReadNewestFirst() {
        let all = [
            event("early", session: "task", createdAt: 1_000),
            event("late", session: "task", createdAt: 9_000),
        ]
        XCTAssertEqual(
            TaskUsageHistory.events(all, sessionIds: ["task"]).map(\.name), ["late", "early"]
        )
    }

    func testTotalsSumCpuAndTakeThePeak() {
        let all = [
            event("a", session: "task", cpuMs: 400, peak: 100),
            event("b", session: "task", createdAt: 2_000, cpuMs: 600, peak: 900),
            event("c", session: "task", createdAt: 3_000, outcome: .error),
        ]
        let totals = TaskUsageHistory.totals(all, sessionIds: ["task"])
        XCTAssertEqual(totals?.calls, 3)
        XCTAssertEqual(totals?.failures, 1)
        // CPU is spent per call and adds up; memory is a level, so the peak wins.
        XCTAssertEqual(totals?.cpuTimeMs, 1_000)
        XCTAssertEqual(totals?.peakMemoryBytes, 900)
    }

    func testATaskThatRanNothingReportsNothing() {
        XCTAssertNil(TaskUsageHistory.totals([], sessionIds: ["task"]))
        XCTAssertTrue(TaskUsageHistory.summaries([], sessionIds: ["task"]).isEmpty)
        // Observed calls with no resource still count, without inventing cost.
        let totals = TaskUsageHistory.totals(
            [event("a", session: "task")], sessionIds: ["task"]
        )
        XCTAssertEqual(totals?.calls, 1)
        XCTAssertNil(totals?.cpuTimeMs)
        XCTAssertNil(totals?.peakMemoryBytes)
    }

    @MainActor
    func testTheHistoryRendersEmptyAndPopulated() {
        // The store is a singleton; a session id nothing else uses keeps this
        // test from reading another test's calls.
        let store = CapabilityUsageStore.shared
        let mine = "task-\(UUID().uuidString)"
        RenderProbe.render(TaskUsageHistoryView(sessionIds: ["absent-\(mine)"], usage: store))

        store.record(.mcp, name: "github", sessionId: mine, sourceId: "src-\(mine)",
                     createdAt: Date().timeIntervalSince1970 * 1_000, toolName: "github")
        RenderProbe.render(TaskUsageHistoryView(sessionIds: [mine], usage: store))
        XCTAssertEqual(
            TaskUsageHistory.events(store.events, sessionIds: [mine]).count, 1
        )
    }
}
