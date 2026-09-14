import SwiftUI
import UIKit
import XCTest
@testable import GrantTap

/// The breakdown answers "where did the period go", so it is ordered by time
/// spent rather than by how often something was called.
final class UsageBreakdownTests: XCTestCase {
    private func summary(
        _ name: String, kind: CapabilityUsageKind = .mcp,
        count: Int, averageDurationMs: Int?, failures: Int = 0
    ) -> OperationalToolSummary {
        OperationalToolSummary(
            kind: kind, name: name, count: count, failures: failures, cancelled: 0,
            averageDurationMs: averageDurationMs, lastUsedAt: 1
        )
    }

    func testOneLongCallOutweighsManyQuickOnes() {
        let shares = UsageBreakdown.shares([
            summary("chatty", count: 100, averageDurationMs: 10),      // 1 000 ms
            summary("slow", count: 2, averageDurationMs: 9_000),       // 18 000 ms
        ])
        XCTAssertEqual(shares.map(\.name), ["slow", "chatty"])
        XCTAssertEqual(shares.first?.fraction, 1)
        // The quick one is still drawn, just short.
        XCTAssertLessThan(try XCTUnwrap(shares.last?.fraction), 0.1)
    }

    func testAToolWithNoMeasuredDurationStillAppears() {
        // Falling back to call count keeps it visible instead of dropping it.
        let shares = UsageBreakdown.shares([
            summary("unmeasured", count: 4, averageDurationMs: nil),
        ])
        XCTAssertEqual(shares.map(\.name), ["unmeasured"])
        XCTAssertEqual(shares.first?.fraction, 1)
    }

    func testNothingMeasurableDrawsNothing() {
        XCTAssertTrue(UsageBreakdown.shares([]).isEmpty)
        // A zero denominator must not render as a confident full bar.
        XCTAssertTrue(UsageBreakdown.shares([
            summary("idle", count: 0, averageDurationMs: 0),
        ]).isEmpty)
    }

    func testTheChartStaysShortAndCarriesFailures() {
        let many = (0..<20).map { index in
            summary("tool-\(index)", count: 20 - index, averageDurationMs: 100, failures: index)
        }
        let shares = UsageBreakdown.shares(many)
        XCTAssertEqual(shares.count, 6, "a chart nobody can read is not a chart")
        XCTAssertEqual(shares.first?.name, "tool-0")
        XCTAssertEqual(shares.first?.failures, 0)
        XCTAssertEqual(shares.last?.failures, 5)
    }

    @MainActor
    func testTheChartRenders() {
        let shares = UsageBreakdown.shares([
            summary("github", count: 3, averageDurationMs: 800, failures: 1),
            summary("review", kind: .skill, count: 2, averageDurationMs: 200),
            summary("bash", kind: .cli, count: 9, averageDurationMs: 50),
        ])
        XCTAssertEqual(shares.count, 3)
        let controller = UIHostingController(rootView: UsageBreakdownChart(shares: shares))
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 300)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
    }
}
