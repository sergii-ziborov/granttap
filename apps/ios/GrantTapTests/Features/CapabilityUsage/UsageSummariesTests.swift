import XCTest
@testable import GrantTap

/// Usage answers for the period the picker offers, not for the slice of events
/// that survived the transport budget.
@MainActor
final class UsageSummariesTests: XCTestCase {
    private let now = 1_800_000_000_000.0

    func testPublishedTotalsCountThePeriodTheEventsCannotCover() {
        // The phone holds a few recent shell calls; the computer counted a week.
        let events = (0..<3).map { index in
            CapabilityUsageEvent(
                id: "bash-\(index)", sourceId: "bash-\(index)", kind: .cli, name: "Bash",
                createdAt: now - Double(index) * 1_000, toolName: "Bash", durationMs: 120
            )
        }
        let totals = [
            CapabilityUsageTotal(windowHours: 168, kind: .cli, name: "Bash",
                                 count: 6_157, failures: 4, cancelled: 0, lastUsedAt: now),
            CapabilityUsageTotal(windowHours: 168, kind: .skill, name: "release-check",
                                 count: 6, failures: 0, cancelled: 0,
                                 lastUsedAt: now - 48 * 3_600_000),
        ]
        let summaries = UsageSummaries(events: events, totals: totals)

        XCTAssertEqual(summaries.toolCalls, 6_163)
        XCTAssertEqual(summaries.rows.first?.name, "Bash", "failures sort first")
        XCTAssertEqual(summaries.rows.first?.count, 6_157)
        XCTAssertEqual(summaries.rows.first?.averageDurationMs, 120, "durations come from events")
        let skill = summaries.rows.first { $0.kind == .skill }
        XCTAssertEqual(skill?.count, 6, "a skill used two days ago is no longer invisible")
        XCTAssertNil(skill?.averageDurationMs, "totals carry no duration, and none is invented")
    }

    func testWithoutPublishedTotalsTheObservedEventsStillAnswer() {
        let events = [
            CapabilityUsageEvent(id: "a", sourceId: "a", kind: .mcp, name: "granttap",
                                 createdAt: now, toolName: "notify", durationMs: 40,
                                 outcome: .error,
                                 resource: CapabilityResourceUsage(
                                    attribution: .measured, cpuTimeMs: 24,
                                    peakRssBytes: 112_000_000
                                 )),
            CapabilityUsageEvent(id: "b", sourceId: "b", kind: .mcp, name: "granttap",
                                 createdAt: now - 1_000, toolName: "notify", durationMs: 60,
                                 resource: CapabilityResourceUsage(
                                    attribution: .measured, cpuTimeMs: 6,
                                    peakRssBytes: 96_000_000
                                 )),
        ]
        let summaries = UsageSummaries(events: events, totals: [])
        XCTAssertEqual(summaries.toolCalls, 2)
        XCTAssertEqual(summaries.rows.count, 1)
        XCTAssertEqual(summaries.rows.first?.failures, 1)
        XCTAssertEqual(summaries.rows.first?.averageDurationMs, 50)
        XCTAssertEqual(summaries.rows.first?.peakMemoryBytes, 112_000_000)
        XCTAssertEqual(summaries.rows.first?.cpuTimeMs, 30)
    }

    func testResourceFallbacksAndFormattingRemainEvidenceBased() {
        let split = CapabilityResourceUsage(
            attribution: .estimated, cpuUserMs: 18, cpuSystemMs: 6,
            rssStartBytes: 4_096, rssEndBytes: 8_192
        )
        let empty = CapabilityResourceUsage(attribution: .unknown)

        XCTAssertEqual(split.effectiveCpuTimeMs, 24)
        XCTAssertEqual(split.effectivePeakRssBytes, 8_192)
        XCTAssertNil(empty.effectiveCpuTimeMs)
        XCTAssertNil(empty.effectivePeakRssBytes)
        XCTAssertEqual(CapabilityResourceFormat.bytes(512), "512 B")
        XCTAssertEqual(CapabilityResourceFormat.bytes(1_536), "1.5 KB")
        XCTAssertNil(CapabilityResourceUsage(
            attribution: .unknown, cpuTimeMs: -1, peakRssBytes: -1
        ).effectiveCpuTimeMs)
        XCTAssertNil(OperationalToolSummary(
            kind: .cli, name: "git", count: 1, failures: 0, cancelled: 0,
            averageDurationMs: nil, lastUsedAt: now
        ).resourceDetail)

        let saturated = UsageSummaries(events: [
            CapabilityUsageEvent(
                id: "max", sourceId: "max", kind: .cli, name: "git", createdAt: now,
                resource: CapabilityResourceUsage(attribution: .estimated, cpuTimeMs: Int.max)
            ),
            CapabilityUsageEvent(
                id: "one", sourceId: "one", kind: .cli, name: "git", createdAt: now - 1,
                resource: CapabilityResourceUsage(attribution: .estimated, cpuTimeMs: 1)
            ),
        ], totals: [])
        XCTAssertEqual(saturated.rows.first?.cpuTimeMs, Int.max)
    }

    func testFailedFilterIncludesOnlyRowsAndEventsThatActuallyFailed() {
        let failed = OperationalToolSummary(
            kind: .cli, name: "Bash", count: 9, failures: 2, cancelled: 0,
            averageDurationMs: nil, lastUsedAt: now
        )
        let healthy = OperationalToolSummary(
            kind: .mcp, name: "granttap", count: 4, failures: 0, cancelled: 0,
            averageDurationMs: nil, lastUsedAt: now
        )
        let error = CapabilityUsageEvent(
            id: "error", sourceId: "error", kind: .cli, name: "Bash",
            createdAt: now, outcome: .error
        )
        let success = CapabilityUsageEvent(
            id: "success", sourceId: "success", kind: .cli, name: "Bash",
            createdAt: now, outcome: .success
        )

        XCTAssertTrue(UsageKindFilter.failed.includes(failed))
        XCTAssertFalse(UsageKindFilter.failed.includes(healthy))
        XCTAssertTrue(UsageKindFilter.failed.includes(error))
        XCTAssertFalse(UsageKindFilter.failed.includes(success))
        let total = CapabilityUsageTotal(
            windowHours: 24, kind: .cli, name: "Bash", count: 465,
            failures: 5, cancelled: 3, lastUsedAt: now
        )
        XCTAssertEqual(UsageKindFilter.failed.selectedTotal(total)?.count, 5)
        XCTAssertEqual(UsageKindFilter.failed.selectedTotal(total)?.cancelled, 0)
    }

    func testTotalsFromSeveralComputersAddUpForTheSelectedWindow() {
        let store = CapabilityTotalsStore.shared
        store.apply([
            CapabilityUsageTotal(windowHours: 168, kind: .cli, name: "Bash",
                                 count: 10, failures: 1, cancelled: 0, lastUsedAt: now),
            CapabilityUsageTotal(windowHours: 168, kind: .cli, count: 10, failures: 1,
                                 cancelled: 0, lastUsedAt: now),
        ], fromRoom: "mac")
        store.apply([
            CapabilityUsageTotal(windowHours: 168, kind: .cli, name: "Bash",
                                 count: 5, failures: 0, cancelled: 2, lastUsedAt: now - 10),
            CapabilityUsageTotal(windowHours: 168, kind: .cli, count: 5, failures: 0,
                                 cancelled: 2, lastUsedAt: now - 10),
        ], fromRoom: "workstation")
        defer {
            store.apply(nil, fromRoom: "mac")
            store.apply(nil, fromRoom: "workstation")
        }

        XCTAssertEqual(store.window(forDays: 7), 168)
        XCTAssertNil(store.window(forDays: 30), "an unpublished window is never invented")
        XCTAssertEqual(store.named(windowHours: 168).first?.count, 15)
        XCTAssertEqual(store.total(kind: .cli, windowHours: 168)?.failures, 1)
        XCTAssertEqual(store.total(kind: .cli, windowHours: 168)?.cancelled, 2)
        XCTAssertNil(store.total(kind: .skill, windowHours: 168))
    }
}
