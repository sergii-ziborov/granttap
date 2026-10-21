import XCTest
@testable import GrantTap

@MainActor
final class CapabilityExecutionUsageTests: XCTestCase {
    private func evidence() -> CapabilityExecutionSummary {
        .init(sessionId: "task", agent: "codex", kind: .mcp, name: "code-review", count: 350,
              failures: 2, cancelled: 1, lastUsedAt: Date().timeIntervalSince1970 * 1_000 + 1000,
              durationMs: 7000, durationCount: 350, source: "native-history")
    }

    func testEmptyOrOlderSnapshotsCannotEraseKnownUsageAndNativeEvidenceWinsOverPreview() {
        let store = CapabilityExecutionUsageStore()
        let row = evidence()
        store.apply([row], fromRoom: "owner", generatedAt: 100)
        store.apply(nil, fromRoom: "owner", generatedAt: 101)
        store.apply([], fromRoom: "owner", generatedAt: 102)
        var partial = row
        partial.count = 1
        store.apply([partial], fromRoom: "owner", generatedAt: 99)
        XCTAssertEqual(store.byRoom["owner"]?.first?.count, 350)
        let preview = CapabilityExecutionSummary(sessionId: row.sessionId, agent: row.agent,
            kind: row.kind, name: row.name, count: 1, failures: 0, cancelled: 0,
            lastUsedAt: row.lastUsedAt, source: "transcript")
        store.apply([preview], fromRoom: "owner", generatedAt: 103)
        XCTAssertEqual(store.byRoom["owner"]?.first?.source, "native-history")
        store.clear()
        XCTAssertTrue(store.byRoom.isEmpty)
    }

    func testInvalidCountersAndExpiredEvidenceStayUnknown() {
        let store = CapabilityExecutionUsageStore()
        var invalid = evidence()
        invalid.failures = invalid.count + 1
        store.apply([invalid], fromRoom: "owner", generatedAt: 100)
        XCTAssertEqual(store.byRoom["owner"]?.count, 0)
        invalid = evidence()
        invalid.lastUsedAt -= 40 * 86_400_000
        store.apply([invalid], fromRoom: "owner", generatedAt: 101)
        XCTAssertEqual(store.byRoom["owner"]?.count, 0)
    }
}
