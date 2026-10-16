import XCTest
@testable import GrantTap

final class UsageRenderingPerformanceTests: XCTestCase {
    func testReadingASummaryForVisibleRowsDoesNotRepeatAggregation() {
        let events = (0..<1_000).map { i in
            CapabilityUsageEvent(id: "busy-\(i)", sourceId: "busy-\(i)", agent: "codex",
                kind: .cli, name: "tool-\(i % 128)", createdAt: 100_000 + Double(i),
                durationMs: 300, outcome: .success)
        }
        let totals = (0..<128).map { i in
            CapabilityUsageTotal(windowHours: 168, kind: .cli, name: "tool-\(i)",
                count: 10, failures: 0, cancelled: 0, lastUsedAt: 101_000)
        }
        let summary = UsageSummaries(events: events, totals: totals)
        let start = ProcessInfo.processInfo.systemUptime
        var visibleCalls = 0
        var visibleRows = 0
        for _ in 0..<200 {
            visibleCalls += summary.toolCalls
            visibleRows += summary.rows.count
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        XCTAssertEqual(visibleCalls, 256_000)
        XCTAssertEqual(visibleRows, 25_600)
        let evidence = XCTAttachment(string: "200 row reads, 1000 events, 128 published totals: \(elapsed) seconds")
        evidence.name = "Usage summary read time"
        evidence.lifetime = .keepAlways
        add(evidence)
        XCTAssertLessThan(elapsed, 0.1, "Rendering rows must reuse the period's already counted totals.")
    }
}
