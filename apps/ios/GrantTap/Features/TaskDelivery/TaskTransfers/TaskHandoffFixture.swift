#if DEBUG
import Foundation

@MainActor
enum TaskHandoffFixture {
    static func apply(to model: AppModel, snapshot: inout ProjectMeshSnapshot, at now: Double) {
        guard ProcessInfo.processInfo.environment["GRANTTAP_TEST_RESUMED_TRANSFER"] == "1" else { return }
        let source = AppModelDemoFixtures.claudeSessionId
        for index in snapshot.executions.indices where snapshot.executions[index].sessionId == source {
            snapshot.executions[index].endedAt = now - 300_000
            snapshot.executions[index].updatedAt = now
            snapshot.executions[index].uncommitted = true
        }
        for index in model.sessions.indices where model.sessions[index].sessionId == source {
            model.sessions[index].lastActivityAt = now - 60_000
        }
        let room = "handoff-test-room"
        let pairing = Pairing(relayUrl: "ws://127.0.0.1:1", room: String(repeating: "t", count: 32),
            role: "phone", deviceName: "Review Mac", senderId: "fixture", myPublicKey: "fixture-public",
            mySecretKey: "fixture-secret", peerPublicKey: "fixture-peer")
        model.connectionRegistry = .init(connections: [.init(id: room, pairing: pairing, label: "Review Mac",
            addedAt: now, lastCatalogAt: now, lastMachineName: "Review Mac")], preferredId: room)
        model.sessionSourceRooms[source] = [room]
        model.meshComputerRoomByEndpointId["MacBook"] = room
        model.agentMeshPreferences = .defaults
        // Cached connection metadata exists, but no transport is available.
        model.relaysByRoom = [:]
    }
}
#endif
