import SwiftUI
import XCTest
@testable import GrantTap

@MainActor final class ProviderAccountUsageTests: XCTestCase {
    private func report(_ at: Double, used: Double = 25) -> ProviderAccountUsage {
        ProviderAccountUsage(provider: "codex", limitId: "codex", observedAt: at,
            windows: [.init(id: "primary", usedPercent: used, windowMinutes: 300, resetsAt: 999_000)])
    }

    func testLatestReportDeduplicatesProjectsWithoutMergingDifferentComputers() {
        let old = ProjectEndpointModelCatalog(endpointId: "one", observedAt: 1, models: [], accountUsage: [report(1)])
        let new = ProjectEndpointModelCatalog(endpointId: "one", observedAt: 2, models: [], accountUsage: [report(2, used: 40)])
        let other = ProjectEndpointModelCatalog(endpointId: "two", observedAt: 2, models: [], accountUsage: [report(2)])
        let rows = ProviderAccountUsageRow.resolve([new, old, other])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].usage.windows[0].remainingPercent, 60)
        XCTAssertTrue(ProviderAccountUsageRow.resolve([new], provider: "claude").isEmpty)
        XCTAssertTrue(rows[0].isCurrent(at: 100))
        XCTAssertFalse(rows[0].isCurrent(at: 400_000))
        XCTAssertFalse(rows[0].isCurrent(at: -100_000))
    }

    func testUnknownAndInvalidLimitsCannotBecomeZeroOrUnlimited() throws {
        XCTAssertFalse(report(10, used: 101).isValid)
        XCTAssertFalse(report(10, used: -.infinity).isValid)
        XCTAssertTrue(ProviderAccountUsageRow.resolve([]).isEmpty)
        let data = try JSONEncoder().encode(report(10))
        XCTAssertEqual(try JSONDecoder().decode(ProviderAccountUsage.self, from: data), report(10))
        let row = ProviderAccountUsageRow(endpointId: "mac", usage: report(10))
        RenderProbe.render(ProviderAccountUsageRows(rows: [row], now: 100), height: 220)
        RenderProbe.render(ProviderAccountUsageRows(rows: [row, row], now: 500_000), height: 320)
    }
}
