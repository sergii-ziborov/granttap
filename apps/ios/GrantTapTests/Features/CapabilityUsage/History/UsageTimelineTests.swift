import SwiftUI
import UIKit
import XCTest
@testable import GrantTap

/// A period total says what something cost; only a shape over time says when.
final class UsageTimelineTests: XCTestCase {
    private let start: Double = 1_800_000_000_000
    private var end: Double { start + 24 * 3_600_000 }

    private func event(at offsetHours: Double, failed: Bool = false) -> CapabilityUsageEvent {
        CapabilityUsageEvent(
            id: "e\(offsetHours)\(failed)", sourceId: "room:e\(offsetHours)\(failed)",
            kind: .cli, name: "bash", sessionId: "task",
            createdAt: start + offsetHours * 3_600_000, toolName: "bash",
            outcome: failed ? .error : .success
        )
    }

    func testCallsLandInTheSliceTheyHappenedIn() {
        // Two calls in one hour and one much later must not read as a flat day.
        let buckets = UsageTimeline.buckets(
            [event(at: 1), event(at: 1.2), event(at: 20)],
            since: start, until: end, slices: 24
        )
        XCTAssertEqual(buckets.count, 24)
        XCTAssertEqual(buckets[1].calls, 2)
        XCTAssertEqual(buckets[20].calls, 1)
        XCTAssertEqual(buckets[5].calls, 0)
        // The busiest slice is full height; a quieter one is proportionally short.
        XCTAssertEqual(buckets[1].fraction, 1)
        XCTAssertEqual(buckets[20].fraction, 0.5)
    }

    func testFailuresAreCountedWhereTheyFell() {
        let buckets = UsageTimeline.buckets(
            [event(at: 3), event(at: 3.5, failed: true)], since: start, until: end
        )
        XCTAssertEqual(buckets[3].calls, 2)
        XCTAssertEqual(buckets[3].failures, 1)
        XCTAssertEqual(buckets[4].failures, 0)
    }

    func testCallsOutsideTheWindowAreNotDrawn() {
        let buckets = UsageTimeline.buckets(
            [event(at: -5), event(at: 40), event(at: 2)], since: start, until: end
        )
        XCTAssertEqual(buckets.reduce(0) { $0 + $1.calls }, 1)
    }

    func testNothingMeasurableDrawsNothing() {
        XCTAssertTrue(UsageTimeline.buckets([], since: start, until: end).isEmpty)
        // A window with no width would divide every call by nothing.
        XCTAssertTrue(UsageTimeline.buckets([event(at: 1)], since: end, until: start).isEmpty)
        XCTAssertTrue(
            UsageTimeline.buckets([event(at: 1)], since: start, until: end, slices: 0).isEmpty
        )
    }

    @MainActor
    func testTheChartRenders() {
        let buckets = UsageTimeline.buckets(
            [event(at: 1), event(at: 9, failed: true)], since: start, until: end
        )
        RenderProbe.render(UsageTimelineChart(buckets: buckets, accent: .blue), height: 140)
        // A slice where nothing ran still draws, so an empty stretch and the
        // edge of the chart do not look alike.
        RenderProbe.render(
            UsageTimelineChart(
                buckets: UsageTimeline.buckets([event(at: 0)], since: start, until: end),
                accent: .blue
            ), height: 140
        )
        XCTAssertEqual(buckets.count, 24)
    }
}
