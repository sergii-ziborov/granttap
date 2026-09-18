import Foundation

/// What the model does with the computers it is linked to, and with the ids
/// they report: a chat that was remapped still resolves, a pairing is added
/// rather than replacing the others, and the tombstones that keep a stale
/// approval from coming back are bounded.
@MainActor
extension AppModel {
    /// Follow stub→Mac remaps so a still-open TaskChatView does not wire a dead id.
    func resolvedSessionId(_ id: String) -> String {
        var current = id
        var guardCount = 0
        while let next = sessionIdAliases[current], next != current, guardCount < 8 {
            current = next
            guardCount += 1
        }
        return current
    }

    func persistSessionIdAliases() {
        UserDefaults.standard.set(sessionIdAliases, forKey: "granttap.session-id-aliases")
    }

    /// Adds a linked computer (does not silently replace others).
    @discardableResult
    func setPairing(_ p: Pairing) -> Bool {
        addConnection(p, mode: .add, prefer: true)
    }

    /// Scan of a new PC joins this iPhone's room. It does not mint a second room.
    func admitScannedComputer(
        _ candidate: Pairing,
        sendJoin: ((Pairing, Pairing) async -> Bool)? = nil
    ) async -> Bool {
        let existing = connectionRegistry.preferred?.pairing
        guard PairingJoinLogic.shouldJoinExistingRoom(existing: existing, candidate: candidate),
              let existing else {
            return addConnection(candidate, mode: .add, prefer: true)
        }
        let sent = await (sendJoin ?? PairingJoinSender.send)(existing, candidate)
        guard sent else {
            append(Self.pairingJoinFailureMessage)
            return false
        }
        let next = PairingJoinLogic.remembered(existing, machinePublicKey: candidate.peerPublicKey)
        return addConnection(next, mode: .add, prefer: true)
    }

    static var pairingStorageFailureMessage: String {
        L("Pairing could not be stored securely — no computer links were changed.")
    }

    static var pairingJoinFailureMessage: String {
        L("This computer did not join the room. Keep GrantTap running on that PC and scan again.")
    }

    static let approvalTombstoneRetentionMs = 24 * 60 * 60 * 1_000.0
    static let approvalTombstoneLimit = 600
}
