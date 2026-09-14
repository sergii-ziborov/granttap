import Foundation

/// Sample observations for Demo mode, kept beside the Usage screen instead of
/// inside it so the screen holds only how numbers are derived.
enum UsageDemoFixtures {
    static func events(now: Double = Date().timeIntervalSince1970 * 1_000)
    -> [CapabilityUsageEvent] {
        [
            CapabilityUsageEvent(id: "demo-mcp-1", sourceId: "demo:mcp:1",
                                 agent: "codex", model: "gpt-5.6-sol", kind: .mcp,
                                 name: "github", sessionId: AppModelDemoFixtures.codexSessionId,
                                 createdAt: now - 90_000, toolName: "search_issues",
                                 durationMs: 840, outcome: .success,
                                 resource: CapabilityResourceUsage(
                                    attribution: .measured, cpuTimeMs: 24,
                                    peakRssBytes: 117_440_512, processCount: 2,
                                    sampleWindowMs: 840
                                 )),
            CapabilityUsageEvent(id: "demo-cli-1", sourceId: "demo:cli:1",
                                 agent: "codex", model: "gpt-5.6-sol", kind: .cli,
                                 name: "rg", sessionId: AppModelDemoFixtures.codexSessionId,
                                 createdAt: now - 150_000, toolName: "exec_command",
                                 durationMs: 120, outcome: .success),
            CapabilityUsageEvent(id: "demo-skill-1", sourceId: "demo:skill:1",
                                 agent: "claude", model: "claude-opus-4-1", kind: .skill,
                                 name: "documents", sessionId: "claude-review-demo",
                                 createdAt: now - 240_000, toolName: "documents",
                                 durationMs: 1_450, outcome: .error, errorClass: "timeout",
                                 resource: CapabilityResourceUsage(
                                    attribution: .attributed, cpuTimeMs: 31,
                                    peakRssBytes: 167_772_160, processCount: 3,
                                    sampleWindowMs: 1_450
                                 ))
        ]
    }
}
