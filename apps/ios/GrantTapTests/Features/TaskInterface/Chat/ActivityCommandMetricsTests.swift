import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class ActivityCommandMetricsTests: XCTestCase {
    func testMeasuredCpuUsesItsOwnWindowAndCanExceedOneCore() throws {
        let resource = CapabilityResourceUsage(attribution: .measured, cpuUserMs: 2000,
            cpuSystemMs: 500, rssStartBytes: 100, rssEndBytes: 200,
            peakRssBytes: 150, childPeakRssBytes: 300, sampleWindowMs: 1000)
        let entry = command(resource, duration: 1200, context: 320)
        let metrics = ActivityCommandMetrics(entry: entry)
        XCTAssertEqual(metrics.averageCpuPercent, 250)
        XCTAssertEqual(metrics.cpuTimeMs, 2500)
        XCTAssertEqual(metrics.peakMemoryBytes, 300)
        XCTAssertEqual(metrics.durationMs, 1200)
        XCTAssertEqual(metrics.contextTokens, 320)
        XCTAssertFalse(metrics.approximate)
        XCTAssertEqual(metrics.source, L("Measured for this call"))
        let decoded = try JSONDecoder().decode(ActivityEntry.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(ActivityCommandMetrics(entry: decoded).resource, resource)
        render(entry)
    }

    func testAttributedAndEstimatedEvidenceRemainsClearlyQualified() {
        for attribution in [CapabilityResourceAttribution.attributed, .estimated] {
            let entry = command(.init(attribution: attribution, cpuTimeMs: 7500,
                peakRssBytes: 300000000, sampleWindowMs: 10000))
            let metrics = ActivityCommandMetrics(entry: entry)
            XCTAssertTrue(metrics.approximate)
            XCTAssertEqual(metrics.averageCpuPercent, 75)
            XCTAssertEqual(metrics.source, attribution == .attributed
                ? L("Approximate share of agent processes") : L("Estimated resources"))
            XCTAssertFalse(metrics.resourceNote.isEmpty)
            render(entry)
        }
        let server = command(.init(attribution: .attributed, peakRssBytes: 1024), kind: .mcp)
        XCTAssertEqual(ActivityCommandMetrics(entry: server).source, L("Nearby MCP server sample"))
        XCTAssertNil(ActivityCommandMetrics(entry: server).averageCpuPercent)
        render(server)
    }

    func testUnknownHistoryAndIncompleteSamplesNeverBecomeZeroOrCpuGuesses() {
        var entry = command(nil)
        entry.capabilities = nil
        let unknown = ActivityCommandMetrics(entry: entry)
        XCTAssertNil(unknown.durationMs)
        XCTAssertNil(unknown.contextTokens)
        XCTAssertNil(unknown.cpuTimeMs)
        XCTAssertNil(unknown.peakMemoryBytes)
        XCTAssertNil(unknown.averageCpuPercent)
        XCTAssertEqual(unknown.source, L("Not reported"))
        render(entry)
        let noWindow = ActivityCommandMetrics(entry: command(.init(attribution: .measured, cpuTimeMs: 10), duration: 100))
        XCTAssertNil(noWindow.averageCpuPercent, "duration is not an observed sampling window")
        let untrusted = ActivityCommandMetrics(entry: command(.init(attribution: .unknown,
            cpuTimeMs: 10, peakRssBytes: 100, sampleWindowMs: 100)))
        XCTAssertNil(untrusted.resource)
        render(untrusted.entry)
    }

    func testZeroNegativeAndDuplicateReportsKeepTheirMeaning() {
        var entry = command(.init(attribution: .measured, cpuTimeMs: 0,
            peakRssBytes: 0, sampleWindowMs: 10), duration: 0, context: 0)
        let zero = ActivityCommandMetrics(entry: entry)
        XCTAssertEqual(zero.averageCpuPercent, 0)
        XCTAssertEqual(zero.cpuTimeMs, 0)
        XCTAssertEqual(zero.peakMemoryBytes, 0)
        XCTAssertEqual(zero.contextTokens, 0)
        render(entry)
        entry.durationMs = -1
        entry.estimatedContextTokens = -1
        XCTAssertNil(ActivityCommandMetrics(entry: entry).durationMs)
        XCTAssertNil(ActivityCommandMetrics(entry: entry).contextTokens)
        var capability = entry.capabilities![0]
        entry.capabilities = [capability, capability]
        XCTAssertEqual(ActivityCommandMetrics(entry: entry).cpuTimeMs, 0, "duplicates are not summed")
        capability.resource = .init(attribution: .measured, cpuTimeMs: 20, sampleWindowMs: 10)
        entry.capabilities?.append(capability)
        XCTAssertNil(ActivityCommandMetrics(entry: entry).resource, "ambiguous resources are not combined")
        render(entry)
        let zeroWindow = ActivityCommandMetrics(entry: command(.init(attribution: .measured,
            cpuTimeMs: 1, sampleWindowMs: 0)))
        XCTAssertNil(zeroWindow.averageCpuPercent)
    }

    func testLegacyCapabilityFieldsSupplyMissingContextAndDurationOnce() {
        var entry = command(nil)
        entry.capabilities?[0].durationMs = 30
        entry.capabilities?[0].estimatedContextTokens = 10
        XCTAssertEqual(ActivityCommandMetrics(entry: entry).durationMs, 30)
        XCTAssertEqual(ActivityCommandMetrics(entry: entry).contextTokens, 10)
        let duplicate = entry.capabilities![0]
        entry.capabilities?.append(duplicate)
        XCTAssertNil(ActivityCommandMetrics(entry: entry).durationMs)
        XCTAssertNil(ActivityCommandMetrics(entry: entry).contextTokens)
    }

    private func command(_ resource: CapabilityResourceUsage?, duration: Int? = nil,
                         context: Int? = nil, kind: CapabilityUsageKind = .cli) -> ActivityEntry {
        let capability = ObservedCapability(kind: kind, name: "test", toolName: "Bash",
            commandPreview: nil, estimatedContextTokens: nil, estimatedBaselineTokens: nil,
            durationMs: nil, outcome: .success, resource: resource)
        return ActivityEntry(id: "call", kind: "tool", text: "Bash: test", createdAt: 1,
            toolName: "Bash", capabilities: [capability], durationMs: duration,
            outcome: .success, estimatedContextTokens: context)
    }

    private func render(_ entry: ActivityEntry) {
        let host = UIHostingController(rootView: NavigationView {
            ActivityStepDetail(step: ActivityStep(entry: entry), accent: .blue)
        })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 900, height: 1200))
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
    }
}
