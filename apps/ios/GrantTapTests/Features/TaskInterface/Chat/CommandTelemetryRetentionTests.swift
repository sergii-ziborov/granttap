import XCTest
@testable import GrantTap

@MainActor
final class CommandTelemetryRetentionTests: XCTestCase {
    func testSparseRefreshKeepsRecordedMetricsInDurableActivity() throws {
        let old = call()
        var sparse = old
        sparse.durationMs = nil
        sparse.estimatedContextTokens = nil
        sparse.capabilities = nil
        let merged = merge(old, sparse)
        XCTAssertEqual(merged.entries[0].durationMs, 20)
        XCTAssertEqual(merged.entries[0].estimatedContextTokens, 10)
        XCTAssertEqual(merged.entries[0].capabilities, old.capabilities)
        let stored = SessionActivityPersistence.bounded(["s": merged])["s"]!
        let restored = try JSONDecoder().decode(SessionActivity.self, from: JSONEncoder().encode(stored))
        XCTAssertEqual(restored.entries[0], merged.entries[0])
    }

    func testFreshEvidenceAndCapabilityOutcomeWinWithoutMixingSamplingWindows() {
        let old = call()
        var fresh = old
        fresh.durationMs = 30
        fresh.estimatedContextTokens = 12
        fresh.capabilities?[0].resource = .init(attribution: .measured, peakRssBytes: 200)
        fresh.capabilities?[0].outcome = .error
        XCTAssertEqual(merge(old, fresh).entries[0], fresh)
        var sparse = old
        sparse.capabilities?[0].resource = nil
        sparse.capabilities?[0].durationMs = nil
        sparse.capabilities?[0].estimatedContextTokens = nil
        sparse.capabilities?[0].outcome = .error
        let kept = merge(old, sparse).entries[0].capabilities![0]
        XCTAssertEqual(kept.resource, old.capabilities![0].resource)
        XCTAssertEqual(kept.durationMs, 20)
        XCTAssertEqual(kept.estimatedContextTokens, 10)
        XCTAssertEqual(kept.outcome, .error)
    }

    func testDifferentToolAndCapabilityNeverInheritResources() {
        let old = call()
        var fresh = old
        fresh.toolName = "Read"
        fresh.capabilities = nil
        fresh.durationMs = nil
        fresh.estimatedContextTokens = nil
        XCTAssertEqual(merge(old, fresh).entries[0], fresh)
        fresh = old
        fresh.capabilities = [.init(kind: .cli, name: "other", toolName: "Bash",
            commandPreview: nil, estimatedContextTokens: nil, estimatedBaselineTokens: nil, durationMs: nil)]
        XCTAssertNil(merge(old, fresh).entries[0].capabilities?[0].resource)
        let message = ActivityEntry(id: "call", kind: "message", text: "Reclassified", createdAt: 1)
        XCTAssertEqual(merge(old, message).entries[0], message)
        fresh = ActivityEntry(id: "different", kind: "tool", text: "Bash: test", createdAt: 2, toolName: "Bash")
        XCTAssertEqual(merge(old, fresh).entries.last, fresh)
    }

    private func call() -> ActivityEntry {
        ActivityEntry(id: "call", kind: "tool", text: "Bash: test", createdAt: 1, toolName: "Bash",
            capabilities: [.init(kind: .cli, name: "test", toolName: "Bash", commandPreview: nil,
                estimatedContextTokens: 10, estimatedBaselineTokens: nil, durationMs: 20,
                outcome: .success, resource: .init(attribution: .attributed, cpuTimeMs: 10,
                    peakRssBytes: 100, sampleWindowMs: 20))], durationMs: 20, estimatedContextTokens: 10)
    }

    private func merge(_ old: ActivityEntry, _ fresh: ActivityEntry) -> SessionActivity {
        AppModel.mergeActivity(existing: .init(sessionId: "s", agent: "claude", state: "idle", entries: [old], generatedAt: 1),
            incoming: .init(sessionId: "s", agent: "claude", state: "idle", entries: [fresh], generatedAt: 2))
    }
}
