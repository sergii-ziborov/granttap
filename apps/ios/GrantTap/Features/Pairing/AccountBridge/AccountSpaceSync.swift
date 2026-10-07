import Foundation

struct RecoveredAccountConnection {
    let machineId: String
    let pairing: Pairing
}

/// Passkey identifies an account; computer recovery only supplies encrypted routes
/// for Projects and Tasks that remain pinned to their original machines.
enum AccountSpaceSync {
    /// A saved account link does not prove that its phone key still works.
    /// Retry the same room after its last recovery failed to deliver a catalog.
    static func staleQRRoomToRecover(_ registry: ConnectionRegistry, accountId: String,
                                     nowMs: Double = Date().timeIntervalSince1970 * 1_000) -> String? {
        guard let preferred = registry.preferred,
              preferred.linkedAccountId == accountId,
              preferred.linkedMachineId != nil else { return nil }
        let recoveredAt = preferred.lastRecoveredAt ?? 0
        let neverReported = preferred.lastCatalogAt <= 0
            && preferred.addedAt > 0
            && nowMs - max(preferred.addedAt, recoveredAt) >= 120_000
        let stoppedReporting = preferred.lastCatalogAt > 0
            && nowMs - max(preferred.lastCatalogAt, recoveredAt) >= 300_000
        return neverReported || stoppedReporting ? preferred.id : nil
    }

    static func availableMachines(_ machines: [AccountComputer],
                                  linkedMachineIds: Set<String>,
                                  nowMs: Double = Date().timeIntervalSince1970 * 1_000)
        -> [AccountComputer] {
        machines.filter { machine in
            guard let seen = machine.lastSeenAt else { return false }
            return !linkedMachineIds.contains(machine.id)
                && seen <= nowMs + 30_000 && seen >= nowMs - 120_000
        }.sorted {
            if $0.lastSeenAt != $1.lastSeenAt {
                return ($0.lastSeenAt ?? 0) > ($1.lastSeenAt ?? 0)
            }
            return $0.id > $1.id
        }
    }

    static func recover(_ machines: [AccountComputer], session: GrantTapAccountSession,
                        connect: @escaping (AccountComputer, GrantTapAccountSession) async throws -> Pairing = {
                            try await AccountRecovery.connect($0, session: $1)
                        })
        async -> [RecoveredAccountConnection] {
        await withTaskGroup(of: RecoveredAccountConnection?.self) { group in
            for machine in machines {
                group.addTask {
                    guard let pairing = try? await connect(machine, session)
                    else { return nil }
                    return RecoveredAccountConnection(machineId: machine.id, pairing: pairing)
                }
            }
            var links: [RecoveredAccountConnection] = []
            for await link in group {
                if let link { links.append(link) }
            }
            return links
        }
    }
}

@MainActor
extension AppModel {
    func startAccountSpaceSync(force: Bool = false, repairRoomId: String? = nil) {
        #if targetEnvironment(macCatalyst)
        return
        #else
        guard !demoMode, let session = GrantTapAccountAPI.session else { return }
        if accountSpaceSyncTask != nil && !force { return }
        let now = Date().timeIntervalSince1970
        guard force || now - lastAccountSpaceSyncAt >= 60 else { return }
        accountSpaceSyncTask?.cancel()
        let generation = UUID()
        accountSpaceSyncGeneration = generation
        lastAccountSpaceSyncAt = now
        accountSpaceSyncTask = Task {
            defer {
                if accountSpaceSyncGeneration == generation {
                    accountSpaceSyncTask = nil
                    accountSpaceSyncGeneration = nil
                }
            }
            do { try await synchronizeAccountSpace(session, repairRoomId: repairRoomId) }
            catch is CancellationError { return }
            catch { append("account-space-sync: \(error.localizedDescription)") }
        }
        #endif
    }

    func stopAccountSpaceSync() {
        accountSpaceSyncTask?.cancel()
        accountSpaceSyncTask = nil
        accountSpaceSyncGeneration = nil
    }

    func synchronizeAccountSpace(
        _ session: GrantTapAccountSession,
        repairRoomId: String? = nil,
        loadComputers: (GrantTapAccountSession) async throws -> [AccountComputer] = {
            try await AccountRecovery.computers(session: $0)
        },
        recover: ([AccountComputer], GrantTapAccountSession) async -> [RecoveredAccountConnection] = {
            await AccountSpaceSync.recover($0, session: $1)
        },
        currentAccountId: () -> String? = { GrantTapAccountAPI.session?.accountId }
    ) async throws {
        let machines = try await loadComputers(session)
        let roomToRepair = repairRoomId ?? AccountSpaceSync.staleQRRoomToRecover(
            connectionRegistry, accountId: session.accountId)
        let linked = Set(connectionRegistry.connections.compactMap { computer in
            computer.linkedAccountId == session.accountId && computer.id != roomToRepair
                ? computer.linkedMachineId : nil
        })
        let targets = AccountSpaceSync.availableMachines(machines, linkedMachineIds: linked)
        for start in stride(from: 0, to: targets.count, by: 8) {
            try Task.checkCancellation()
            guard currentAccountId() == session.accountId else {
                throw CancellationError()
            }
            let batch = Array(targets[start..<min(start + 8, targets.count)])
            let recovered = await recover(batch, session)
            guard !recovered.isEmpty else { throw AccountBridgeError.unavailable }
            try Task.checkCancellation()
            guard currentAccountId() == session.accountId else {
                throw CancellationError()
            }
            if !recovered.isEmpty, !addRecoveredAccountConnections(recovered,
                                                                    accountId: session.accountId) {
                throw AccountBridgeError.storage
            }
        }
        try await linkLocalComputersToAccount(session)
    }
}
