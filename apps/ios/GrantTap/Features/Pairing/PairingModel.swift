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
            return L("Code did not match. Authenticate again and scan the new QR on granttap.com/connect.")
        case .codeExpiredOrUsed:
            return L("This QR expired or was already used. Authenticate again and scan the new QR on granttap.com/connect.")
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
    /// Other computers in this same pairing room. The phone decrypts each one.
    var extraPeerPublicKeys: [String]? = nil
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

/// Phone half carried so the new computer can stay in this room and re-issue a QR.
struct PairingJoinPhoneCfg: Codable, Equatable {
    var relayUrl: String
    var room: String
    var role: String
    var deviceName: String
    var senderId: String
    var myPublicKey: String
    var mySecretKey: String
    var peerPublicKey: String
    var pushAuth: String?
    var extraPeerPublicKeys: [String]?
}

/// A phone already in a room scanned a new computer. That computer moves here.
struct PairingJoin: Codable, Equatable {
    var type = "pairing.join"
    var room: String
    var relayUrl: String
    var phonePublicKey: String
    var phoneCfg: PairingJoinPhoneCfg
    var createdAt: Double
}

enum PairingJoinLogic {
    /// Live peers decide the room. A leftover pairing file does not.
    /// Solo/offline phone adopts the QR room. A Live phone keeps its room and
    /// the scanned computer joins it. Two Live rooms merge into the phone's.
    static func shouldJoinExistingRoom(
        existing: Pairing?,
        candidate: Pairing,
        phoneHasLivePeer: Bool = false
    ) -> Bool {
        guard let existing, !existing.isHub, !candidate.isHub else { return false }
        guard existing.room != candidate.room else { return false }
        return phoneHasLivePeer
    }

    static func remembered(_ existing: Pairing, machinePublicKey: String, from candidate: Pairing? = nil) -> Pairing {
        var next = existing
        var extras = next.extraPeerPublicKeys ?? []
        if machinePublicKey != next.peerPublicKey, !extras.contains(machinePublicKey) {
            extras.append(machinePublicKey)
        }
        next.extraPeerPublicKeys = extras.isEmpty ? nil : extras
        if (next.pushAuth == nil || next.pushAuth?.isEmpty == true),
           let auth = candidate?.pushAuth, !(auth.isEmpty) {
            next.pushAuth = auth
        }
        return next
    }

    static func payload(existing: Pairing, machinePublicKey: String, now: Double = Date().timeIntervalSince1970 * 1_000) -> PairingJoin {
        let phone = remembered(existing, machinePublicKey: machinePublicKey)
        return PairingJoin(
            room: phone.room,
            relayUrl: phone.relayUrl,
            phonePublicKey: phone.myPublicKey,
            phoneCfg: PairingJoinPhoneCfg(
                relayUrl: phone.relayUrl,
                room: phone.room,
                role: "phone",
                deviceName: phone.deviceName,
                senderId: phone.senderId,
                myPublicKey: phone.myPublicKey,
                mySecretKey: phone.mySecretKey,
                peerPublicKey: phone.peerPublicKey,
                pushAuth: phone.pushAuth,
                extraPeerPublicKeys: phone.extraPeerPublicKeys
            ),
            createdAt: now
        )
    }
}

enum PairingJoinSender {
    /// Speak as the candidate phone half just long enough to move that computer.
    static func send(
        existing: Pairing,
        candidate: Pairing,
        timeout: TimeInterval = 12
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let client = RelayClient(pairing: candidate)
            var finished = false
            let finish: (Bool) -> Void = { ok in
                guard !finished else { return }
                finished = true
                client.disconnect()
                continuation.resume(returning: ok)
            }
            client.onConnectionChange = { up in
                guard up else { return }
                client.send(
                    payload: PairingJoinLogic.payload(existing: existing, machinePublicKey: candidate.peerPublicKey),
                    to: "machine",
                    ttl: 60
                ) { error in
                    finish(error == nil)
                }
            }
            client.connect()
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                finish(false)
            }
        }
    }
}
