#if DEBUG
import Foundation

@MainActor
enum CapabilityUsageFixture {
    static func apply(to model: AppModel, mesh: inout ProjectMeshSnapshot, at now: Double) {
        guard ProcessInfo.processInfo.environment["GRANTTAP_TEST_CAPABILITY_USAGE"] == "1" else { return }
        let endpoint = "Workstation"
        let room = "capability-fixture-room"
        let session = AppModelDemoFixtures.codexSessionId
        model.meshComputerRoomByEndpointId[endpoint] = room
        mesh.skills = []
        mesh.mcpServers = [.init(name: "code-review", provider: "codex", endpointId: endpoint,
            configuredEnabled: true, allowed: true, sessionIds: [session])]
        model.meshSnapshots[mesh.projectId] = mesh
        CapabilityUsageStore.shared.clear()
        CapabilityExecutionUsageStore.shared.apply([
            .init(sessionId: session, agent: "codex", kind: .mcp, name: "code-review", count: 350,
                  failures: 2, cancelled: 0, lastUsedAt: now + 1000,
                  durationMs: 7000, durationCount: 350, source: "native-history"),
            .init(sessionId: session, agent: "codex", kind: .skill, name: "review-workflow", count: 12,
                  failures: 0, cancelled: 0, lastUsedAt: now + 1000, source: "transcript"),
        ], fromRoom: room, generatedAt: now)
    }
}
#endif
