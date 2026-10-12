#if DEBUG
import Foundation

/// Two Macs and three rooms: Alpha's QR and passkey routes share one identity.
@MainActor
enum ConnectionListFixture {
    static func apply(to model: AppModel) {
        let now = Date().timeIntervalSince1970 * 1_000
        for (room, name) in [(String(repeating: "a", count: 32), "Alpha Mac"),
                             (String(repeating: "b", count: 32), "Beta Mac"),
                             (String(repeating: "c", count: 32), "Alpha Mac")] {
            let key = Data(repeating: 7, count: 32).base64EncodedString()
            let pairing = Pairing(relayUrl: "wss://relay.granttap.com", room: room,
                                  role: "phone", deviceName: name, senderId: "fixture-phone",
                                  myPublicKey: key, mySecretKey: key, peerPublicKey: key)
            model.connectionRegistry = ConnectionRegistryLogic.upsert(
                model.connectionRegistry, pairing: pairing, label: name, prefer: false)
            if name == "Alpha Mac",
               let index = model.connectionRegistry.connections.firstIndex(where: { $0.id == room }) {
                model.connectionRegistry.connections[index].accountCredential = .init(
                    accountId: "fixture-account", machineId: "alpha-machine", machineToken: "fixture")
            }
            if room.first == "a" {
                model.pairing = pairing
                model.roomRuntime[room] = .init(socketUp: true, socketUpSince: now,
                                                lastHeartbeatAt: now)
                if let index = model.connectionRegistry.connections.firstIndex(where: { $0.id == room }) {
                    model.connectionRegistry.connections[index].lastCatalogAt = now - 60_000
                }
            }
        }
    }
}
#endif
