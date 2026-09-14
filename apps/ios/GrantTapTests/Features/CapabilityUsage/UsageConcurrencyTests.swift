import XCTest
@testable import GrantTap

final class UsageConcurrencyTests: XCTestCase {
    private func event(_ id: String, kind: CapabilityUsageKind, name: String, at: Double, duration: Int?,
                       outcome: CapabilityOutcome = .success, cpu: Int? = nil, peak: Int? = nil) -> CapabilityUsageEvent {
        var event = CapabilityUsageEvent(id: id, sourceId: id, kind: kind, name: name, createdAt: at)
        event.durationMs = duration
        event.outcome = outcome
        if cpu != nil || peak != nil {
            var resource = CapabilityResourceUsage(attribution: .attributed)
            resource.cpuTimeMs = cpu
            resource.peakRssBytes = peak
            event.resource = resource
        }
        return event
    }

    func testCallsThatOverlapCountAsAtOnceAndSequentialOnesDoNot() {
        // Three searches back to back, then two that overlapped, then a burst of instants.
        let events = [
            event("a", kind: .cli, name: "rg", at: 1_000, duration: 500),
            event("b", kind: .cli, name: "rg", at: 2_000, duration: 500),
            event("c", kind: .cli, name: "rg", at: 3_000, duration: 500),
            event("d", kind: .mcp, name: "github", at: 5_000, duration: 2_000),
            event("e", kind: .mcp, name: "figma", at: 5_500, duration: 1_000),
            event("f", kind: .skill, name: "review", at: 9_000, duration: nil),
            event("g", kind: .skill, name: "review", at: 9_000, duration: 0),
        ]
        XCTAssertEqual(UsageConcurrency.maxParallel(Array(events[0..<3])), 1, "one after another")
        XCTAssertEqual(UsageConcurrency.maxParallel(Array(events[3..<5])), 2, "the second started while the first ran")
        XCTAssertEqual(UsageConcurrency.maxParallel(Array(events[5..<7])), 2, "two instants at one moment are a burst")
        XCTAssertEqual(UsageConcurrency.maxParallel([]), 0)
        XCTAssertEqual(UsageConcurrency.maxParallelByKind(events), [.cli: 1, .mcp: 2, .skill: 2])
        XCTAssertEqual(UsageConcurrency.maxParallelByName(events)["mcp:github"], 1)

        let buckets = UsageConcurrency.buckets(events, since: 0, until: 10_000, slices: 10)
        XCTAssertEqual(buckets.count, 10)
        XCTAssertEqual(buckets[5].calls, 2, "the slice where github and figma overlapped")
        XCTAssertEqual(buckets[1].calls, 1)
        XCTAssertEqual(buckets[0].calls, 1, "a call that started in the slice before is still open here")
        XCTAssertEqual(buckets.map(\.fraction).max(), 1)
        XCTAssertEqual(UsageConcurrency.buckets([], since: 0, until: 1), [])
        XCTAssertEqual(UsageConcurrency.buckets(events, since: 5, until: 1), [])
    }

    func testKindTotalsSumTimeCpuPeakAndAtOnce() {
        let events = [
            event("a", kind: .cli, name: "rg", at: 1_000, duration: 500, cpu: 120, peak: 50_000_000),
            event("b", kind: .cli, name: "npm", at: 1_200, duration: 800, outcome: .error, cpu: 300, peak: 90_000_000),
            event("c", kind: .skill, name: "review", at: 4_000, duration: nil),
        ]
        let rows = UsageKindTotals.rows(events)
        XCTAssertEqual(rows.map(\.kind), [.skill, .cli])
        let cli = try! XCTUnwrap(rows.first { $0.kind == .cli })
        XCTAssertEqual(cli.calls, 2)
        XCTAssertEqual(cli.failures, 1)
        XCTAssertEqual(cli.totalDurationMs, 1_300)
        XCTAssertEqual(cli.cpuTimeMs, 420)
        XCTAssertEqual(cli.peakMemoryBytes, 90_000_000)
        XCTAssertEqual(cli.maxParallel, 2, "npm started while rg was still running")
        XCTAssertEqual(cli.title, "CLI")
        let skill = try! XCTUnwrap(rows.first { $0.kind == .skill })
        XCTAssertEqual(skill.totalDurationMs, 0)
        XCTAssertNil(skill.peakMemoryBytes)
        XCTAssertEqual(skill.title, L("Skills"))
        XCTAssertEqual(UsageKindTotal(kind: .mcp, calls: 1, failures: 0, totalDurationMs: 0, cpuTimeMs: 0, peakMemoryBytes: nil, maxParallel: 1).title, "MCP")
    }
}
