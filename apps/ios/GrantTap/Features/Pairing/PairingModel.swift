import Foundation

/// The phone half of a pairing — identical JSON to `phone.pairing.json`
/// produced by the MCP `connect` tool. It arrives by QR or a high-entropy token and
/// is persisted in the device-only Keychain. Older beta UserDefaults data is
/// migrated once and removed.
enum PairingError: Error {
    case badCode, codeExpiredOrUsed, unreachable, relayError(Int)

    static func forHTTPStatus(_ status: Int) -> PairingError {
        switch status {
        case 404, 410:
            return .codeExpiredOrUsed
        default:
            return .relayError(status)
        }
    }

    var message: String {
        switch self {
        case .badCode:
            return L("Code did not match. Ask the agent to connect GrantTap and generate another QR.")
        case .codeExpiredOrUsed:
            return L("This QR code expired or was already used. Ask the agent for a new QR code.")
        case .unreachable:
            return L("Relay is unavailable. Check its address and try again.")
        case .relayError(let status):
            return String(format: L("Relay returned error %d."), status)
        }
    }
}

struct Pairing: Codable, Equatable {
    struct SecureLink: Equatable {
        let relayBase: String
        let mailboxId: String
        let transferKey: String
    }

    var relayUrl: String
    var room: String
    var role: String        // "phone"
    var deviceName: String
    var senderId: String
    var myPublicKey: String
    var mySecretKey: String
    var peerPublicKey: String
    /// Random relay-only credential used to register APNs tokens. It is not an
    /// encryption key and cannot open GrantTap payloads.
    var pushAuth: String? = nil
    /// The other side is a person's phone forwarding a Project, not a computer.
    /// Minted into the invite by the phone that shares, so the phone that
    /// joins knows what it is talking to.
    var hub: Bool? = nil

    /// A pairing with another person's phone.
    var isHub: Bool { hub == true }

    static let storeKey = "mc.pairing"
    static let keychainService = "com.ziborov.granttap.pairing"

    static let mailboxLength = 32
    static let currentRelaySocket = "wss://relay.granttap.com"
    static let currentRelayHTTP = "https://relay.granttap.com"
    private static let retiredRelaySocket = "wss://granttap-relay.sergii-ziborov.workers.dev"
    private static let retiredRelayHTTP = "https://granttap-relay.sergii-ziborov.workers.dev"

    static func migratedRelayURL(_ value: String) -> String {
        switch value {
        case retiredRelaySocket: return currentRelaySocket
        case retiredRelayHTTP: return currentRelayHTTP
        default: return value
        }
    }

    func migratingRetiredRelay() -> Pairing {
        var pairing = self
        pairing.relayUrl = Self.migratedRelayURL(relayUrl)
        return pairing
    }

    /// Preferred (active) pairing from the multi-computer registry.
    static func load() -> Pairing? {
        PairedConnectionStore.load().preferred?.pairing
    }

    /// Persist by upserting into the multi-computer registry (does not wipe others).
    @discardableResult
    func save() -> Bool {
        let pairing = migratingRetiredRelay()
        guard Pairing.isValid(pairing) else { return false }
        var reg = PairedConnectionStore.load()
        reg = ConnectionRegistryLogic.upsert(reg, pairing: pairing, mode: .add, prefer: true)
        return PairedConnectionStore.save(reg)
    }

    /// Remove every linked computer (legacy name kept for call sites).
    static func remove() {
        PairedConnectionStore.removeAll()
    }

    static func fromJSON(_ text: String) -> Pairing? {
        guard let data = text.data(using: .utf8) else { return nil }
        guard let decoded = try? JSONDecoder().decode(Pairing.self, from: data) else { return nil }
        let pairing = decoded.migratingRetiredRelay()
        guard isValid(pairing) else { return nil }
        return pairing
    }

}
