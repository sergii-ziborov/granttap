import XCTest
@testable import GrantTap

@MainActor
final class UsagePeriodSummaryTests: XCTestCase {
    private func event(_ id: String, kind: CapabilityUsageKind = .cli,
                       agent: String = "codex", at: Double = 500,
                       outcome: CapabilityOutcome = .success) -> CapabilityUsageEvent {
        CapabilityUsageEvent(id: id, sourceId: id, agent: agent, kind: kind,
                             name: id, createdAt: at, outcome: outcome)
    }

    func testToolFiltersKeepOverviewAndSkillTotalsStable() {
        let period = UsagePeriodSummary(events: [event("git"), event("notify", kind: .mcp)],
            totals: [
                CapabilityUsageTotal(windowHours: 168, kind: .cli, count: 200,
                                     failures: 3, cancelled: 0, lastUsedAt: 500),
                CapabilityUsageTotal(windowHours: 168, kind: .skill, name: "release-check",
                                     count: 6, failures: 0, cancelled: 0, lastUsedAt: 200),
            ], since: 100, until: 1_000)
        XCTAssertEqual(period.overview.toolCalls, 207)
        XCTAssertEqual(period.skills.map(\.name), ["release-check"])
        XCTAssertEqual(period.tools(kind: .skill, provider: "all").rows.first?.count, 6)
        XCTAssertEqual(period.tools(kind: .mcp, provider: "all").toolCalls, 1)
        XCTAssertEqual(period.tools(kind: .failed, provider: "all").toolCalls, 3)
        XCTAssertEqual(period.overview.toolCalls, 207)
    }

    func testPeriodAndProviderMatchOnlyTheObservedScope() {
        let period = UsagePeriodSummary(events: [
            event("old", at: 99), event("future", at: 1_001),
            event("git", agent: "Codex"), event("notify", kind: .mcp, agent: "claude"),
        ], totals: [], since: 100, until: 1_000)
        XCTAssertEqual(period.overview.toolCalls, 2)
        XCTAssertEqual(period.tools(kind: .all, provider: "codex").rows.map(\.name), ["git"])
        XCTAssertTrue(period.tools(kind: .skill, provider: "codex").rows.isEmpty)
        XCTAssertEqual(period.tools(kind: .all, provider: "all").toolCalls, 2)
    }

    func testHistoryKeepsTheSelectedPeriodWhenOpeningARow() {
        let history = CapabilityUsageHistoryView(kind: .cli, name: "git", agent: "codex",
                                               modelName: nil, since: 100, until: 1_000)
        XCTAssertTrue(history.matches(event("git", at: 100)))
        XCTAssertTrue(history.matches(event("git", at: 1_000)))
        XCTAssertFalse(history.matches(event("git", at: 99)))
        XCTAssertFalse(history.matches(event("git", at: 1_001)))
        XCTAssertFalse(history.matches(event("git", agent: "claude")))
        XCTAssertFalse(history.matches(event("git", kind: .mcp)))
    }

    func testPublishedTotalsStoreSuppliesRollupsAndNamedRows() {
        let store = CapabilityTotalsStore.shared
        let room = "usage-period-test-\(UUID().uuidString)"
        let rows = [
            CapabilityUsageTotal(windowHours: 720, kind: .cli, count: 100,
                                 failures: 1, cancelled: 0, lastUsedAt: 500),
            CapabilityUsageTotal(windowHours: 720, kind: .cli, name: "git", count: 90,
                                 failures: 1, cancelled: 0, lastUsedAt: 500),
        ]
        store.apply(rows, fromRoom: room)
        defer { store.apply(nil, fromRoom: room) }
        XCTAssertEqual(store.summaries(windowHours: 720).count, 2)
        XCTAssertEqual(UsageSummaries(events: [], totals: store.summaries(windowHours: 720))
            .toolCalls, 100)
    }
}
