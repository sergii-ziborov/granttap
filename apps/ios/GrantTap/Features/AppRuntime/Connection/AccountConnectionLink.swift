import Foundation

extension AppModel {
    /// Persist recovered pairings as one account update without changing the Task route.
    func addRecoveredAccountConnections(_ links: [RecoveredAccountConnection],
                                        accountId: String) -> Bool {
        guard !links.isEmpty, links.allSatisfy({ Pairing.isValid($0.pairing) }),
              Set(links.map(\.pairing.room)).count == links.count else { return false }
        let previous = Dictionary(uniqueKeysWithValues: connectionRegistry.connections.map {
            ($0.id, $0.pairing)
        })
        var candidate = connectionRegistry
        for link in links {
            candidate = ConnectionRegistryLogic.upsert(candidate, pairing: link.pairing,
                                                       mode: .add, prefer: false)
            candidate = ConnectionRegistryLogic.noteAccountRecovery(
                candidate, roomId: link.pairing.room,
                peerPublicKey: link.pairing.peerPublicKey,
                reference: AccountMachineReference(accountId: accountId, machineId: link.machineId))
        }
        guard PairedConnectionStore.save(candidate) else { return false }
        connectionRegistry = candidate
        pairing = candidate.preferred?.pairing
        purgeDemoCatalogResidue(reason: "account-recovery")
        pruneSessionSourceRoomsToLinkedRooms()
        for link in links where previous[link.pairing.room] != link.pairing
            || relaysByRoom[link.pairing.room] == nil {
            attachRelay(for: link.pairing)
        }
        relay = candidate.preferredId.flatMap { relaysByRoom[$0] }
        PushRegistrationManager.shared.pairingDidChange()
        return true
    }

    func clearDeletedAccountLinks(_ accountId: String) throws {
        let candidate = ConnectionRegistryLogic.clearAccountLinks(connectionRegistry,
                                                                   accountId: accountId)
        guard candidate == connectionRegistry || PairedConnectionStore.save(candidate) else {
            throw AccountBridgeError.storage
        }
        connectionRegistry = candidate
    }

    /// Merge QR-linked computers into passkey recovery without changing room routing.
    func linkLocalComputersToAccount(_ session: GrantTapAccountSession,
                                     transport: URLSession = .shared) async throws {
        for computer in connectionRegistry.connections where !computer.pairing.isHub {
            if computer.accountReference != nil {
                // A recovered Mac identity is authoritative for an older QR room.
                // Never register that room again or send its stale credential back.
                continue
            }
            if let existing = computer.accountCredential {
                if existing.accountId != session.accountId { continue }
                sendAccountLink(existing, roomId: computer.id)
                continue
            }
            let credential = try await AccountRecovery.register(computer, session: session,
                                                                transport: transport)
            let candidate = ConnectionRegistryLogic.noteAccountLink(
                connectionRegistry, roomId: computer.id,
                peerPublicKey: computer.pairing.peerPublicKey, credential: credential
            )
            guard candidate != connectionRegistry, PairedConnectionStore.save(candidate) else {
                throw AccountBridgeError.storage
            }
            connectionRegistry = candidate
            sendAccountLink(credential, roomId: computer.id)
        }
    }

    func sendAccountLink(_ credential: AccountMachineCredential, roomId: String) {
        guard let client = relaysByRoom[roomId], client.task != nil else { return }
        client.send(payload: AccountMachineLink(
            accountId: credential.accountId, machineId: credential.machineId,
            machineToken: credential.machineToken,
            createdAt: Date().timeIntervalSince1970 * 1_000
        ), ttl: 15 * 60)
    }
}
