import Foundation

/// A reported packet is distinct from proof that an agent used its context.
enum CortexPacketFixture {
    @MainActor
    static func apply(to model: AppModel, mesh: inout ProjectMeshSnapshot, at now: Double) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["GRANTTAP_TEST_CORTEX_PACKET"] == "1" else { return }
        let packet = ProjectCortexPacketStatus(
            packetId: "sample-packet", snapshotId: "sample-snapshot",
            included: 12, omitted: 6, rawEstimatedTokens: 12_000,
            selectedEstimatedTokens: 8_000, omittedEstimatedTokens: 4_000,
            deduplicatedLines: 90, requiresUpstream: true
        )
        mesh.cortex = [ProjectCortexIntegration(
            projectId: mesh.projectId, endpointId: "Workstation", enabled: true,
            maxTokens: 16_384, state: "succeeded", version: "0.1.1",
            revision: "sample-cortex-revision", weavatrixVersion: "2.17.4",
            packet: packet, checkedAt: now
        )]
        model.meshSnapshots[mesh.projectId] = mesh
        #endif
    }
}
