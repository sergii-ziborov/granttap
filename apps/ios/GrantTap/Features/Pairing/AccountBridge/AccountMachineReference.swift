import Foundation

/// The account identity of a recovered computer. Its machine token remains on the Mac.
struct AccountMachineReference: Codable, Equatable {
    let accountId: String
    let machineId: String
}

extension LinkedComputer {
    var linkedAccountId: String? {
        accountReference?.accountId ?? accountCredential?.accountId
    }

    var linkedMachineId: String? {
        accountReference?.machineId ?? accountCredential?.machineId
    }
}

extension ConnectionRegistryLogic {
    static func noteAccountLink(
        _ reg: ConnectionRegistry, roomId: String, peerPublicKey: String,
        credential: AccountMachineCredential
    ) -> ConnectionRegistry {
        var next = reg
        guard let index = next.connections.firstIndex(where: {
            $0.id == roomId && $0.pairing.peerPublicKey == peerPublicKey && !$0.pairing.isHub
        }) else { return reg }
        next.connections[index].accountCredential = credential
        next.connections[index].accountReference = AccountMachineReference(
            accountId: credential.accountId, machineId: credential.machineId)
        return next
    }

    static func noteAccountRecovery(
        _ reg: ConnectionRegistry, roomId: String, peerPublicKey: String,
        reference: AccountMachineReference,
        nowMs: Double = Date().timeIntervalSince1970 * 1_000
    ) -> ConnectionRegistry {
        var next = reg
        guard let index = next.connections.firstIndex(where: {
            $0.id == roomId && $0.pairing.peerPublicKey == peerPublicKey && !$0.pairing.isHub
        }) else { return reg }
        next.connections[index].accountReference = reference
        next.connections[index].lastRecoveredAt = nowMs
        // Recovery proves the Mac's current account identity. The old QR grant
        // is no longer needed and must not suppress another recovery attempt.
        next.connections[index].accountCredential = nil
        return next
    }

    static func clearAccountLinks(_ reg: ConnectionRegistry,
                                  accountId: String) -> ConnectionRegistry {
        var next = reg
        for index in next.connections.indices where next.connections[index].linkedAccountId == accountId {
            next.connections[index].accountCredential = nil
            next.connections[index].accountReference = nil
        }
        return next
    }
}
