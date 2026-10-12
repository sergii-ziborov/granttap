#if DEBUG
import Foundation

/// In-memory UI fixture: the real invite screen sees a linked computer and a Project Mesh.
@MainActor
enum InviteScopeFixture {
    static func apply(to model: AppModel) {
        let key = Data(repeating: 9, count: 32).base64EncodedString()
        let pairing = Pairing(relayUrl: "wss://relay.granttap.com",
                              room: String(repeating: "a", count: 32), role: "phone",
                              deviceName: "Scope Mac", senderId: "scope-phone",
                              myPublicKey: key, mySecretKey: key, peerPublicKey: key)
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            .empty, pairing: pairing, label: "Scope Mac")
        model.pairing = pairing
        let project = AppModelDemoMeshFixtures.snapshot(at: Date().timeIntervalSince1970 * 1_000)
        model.meshSnapshots = [project.projectId: project]
    }
}
#endif
