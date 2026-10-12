import Foundation

struct RecoveredAccountConnection {
    let machineId: String
    let pairing: Pairing
}

/// Passkey identifies an account; computer recovery only supplies encrypted routes
/// for Projects and Tasks that remain pinned to their original machines.
enum AccountSpaceSync {
    static func staleRoomsToRecover(_ registry: ConnectionRegistry, accountId: String,
                                    nowMs: Double = Date().timeIntervalSince1970 * 1_000)
        -> Set<String> {
        Set(registry.connections.compactMap { computer in
            guard computer.linkedAccountId == accountId,
                  computer.linkedMachineId != nil else { return nil }
            let recoveredAt = computer.lastRecoveredAt ?? 0
            let neverReported = computer.lastCatalogAt <= 0
                && computer.addedAt > 0
                && nowMs - max(computer.addedAt, recoveredAt) >= 120_000
            let stoppedReporting = computer.lastCatalogAt > 0
                && nowMs - max(computer.lastCatalogAt, recoveredAt) >= 300_000
            return neverReported || stoppedReporting ? computer.id : nil
        })
    }

    /// A saved account link does not prove that its phone key still works.
    /// Retry the same room after its last recovery failed to deliver a catalog.
    static func staleQRRoomToRecover(_ registry: ConnectionRegistry, accountId: String,
                                     nowMs: Double = Date().timeIntervalSince1970 * 1_000) -> String? {
        guard let preferred = registry.preferred else { return nil }
        return staleRoomsToRecover(registry, accountId: accountId, nowMs: nowMs)
            .contains(preferred.id) ? preferred.id : nil
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
enum AccountDeviceEnrollment {
    static func join(_ code: String, model: AppModel) async throws {
        _ = try await GrantTapAccountAPI.redeemDeviceInvite(code)
        await SubscriptionStore.shared.refreshBetaRelayAccess()
        model.refreshAccountDeviceCatalog()
        model.startAccountSpaceSync(force: true)
    }
}

@MainActor
extension AppModel {
    func startAccountSpaceSync(force: Bool = false, repairRoomId: String? = nil) {
        #if targetEnvironment(macCatalyst)
        return
        #else
        guard !demoMode, let session = GrantTapAccountAPI.session else { return }
        scheduleAccountSpaceSync(session: session, force: force, repairRoomId: repairRoomId) {
            [weak self] session, room in
            guard let self else { return }
            try await self.synchronizeAccountSpace(session, repairRoomId: room)
        }
        #endif
    }

    func scheduleAccountSpaceSync(
        session: GrantTapAccountSession, force: Bool = false,
        repairRoomId: String? = nil, now: TimeInterval = Date().timeIntervalSince1970,
        synchronize: @escaping @MainActor (GrantTapAccountSession, String?) async throws -> Void
    ) {
        if accountSpaceSyncTask != nil && !force { return }
        guard force || now - lastAccountSpaceSyncAt >= 60 else { return }
        accountSpaceSyncTask?.cancel()
        let generation = UUID()
        accountSpaceSyncGeneration = generation
        accountSpaceSyncError = nil
        lastAccountSpaceSyncAt = now
        accountSpaceSyncTask = Task {
            defer {
                if accountSpaceSyncGeneration == generation {
                    accountSpaceSyncTask = nil
                    accountSpaceSyncGeneration = nil
                }
            }
            do {
                try await synchronize(session, repairRoomId)
                if accountSpaceSyncGeneration == generation { accountSpaceSyncError = nil }
            }
            catch is CancellationError { return }
            catch {
                guard accountSpaceSyncGeneration == generation else { return }
                accountSpaceSyncError = error.localizedDescription
                append("account-space-sync: \(error.localizedDescription)")
            }
        }
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
        let respondingRooms = Set(connectionRegistry.connections.filter {
            snapshotForConnection($0).phase == .live
                || relaysByRoom[$0.id]?.awaitingInitialPeer() == true
        }.map(\.id))
        var roomsToRepair = AccountSpaceSync.staleRoomsToRecover(
            connectionRegistry, accountId: session.accountId).subtracting(respondingRooms)
        if let repairRoomId { roomsToRepair.insert(repairRoomId) }
        let linked = Set(connectionRegistry.connections.compactMap { computer in
            computer.linkedAccountId == session.accountId && !roomsToRepair.contains(computer.id)
                ? computer.linkedMachineId : nil
        })
        let targets = AccountSpaceSync.availableMachines(machines, linkedMachineIds: linked)
        var unrecovered = false
        for start in stride(from: 0, to: targets.count, by: 8) {
            try Task.checkCancellation()
            guard currentAccountId() == session.accountId else {
                throw CancellationError()
            }
            let batch = Array(targets[start..<min(start + 8, targets.count)])
            let recovered = await recover(batch, session)
            if recovered.count < batch.count { unrecovered = true }
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
        if unrecovered { throw AccountBridgeError.recoveryFailed }
    }
}
