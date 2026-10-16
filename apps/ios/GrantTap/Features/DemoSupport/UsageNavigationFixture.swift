#if DEBUG
import Foundation

/// Full retained feed for navigation checks, without writing a user's history.
enum UsageNavigationFixture {
    static func events(now: Double) -> [CapabilityUsageEvent] {
        (0..<1_000).map { index in
            CapabilityUsageEvent(id: "usage-load-\(index)", sourceId: "usage-load-\(index)",
                agent: ["codex", "claude", "cursor", "grok"][index % 4],
                kind: CapabilityUsageKind.allCases[index % 3], name: "observed-tool-\(index % 128)",
                createdAt: now - Double(index * 60_000), durationMs: 30_000,
                outcome: index % 20 == 0 ? .error : .success)
        }
    }
}
#endif
