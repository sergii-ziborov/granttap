import Foundation
import SwiftUI
import UIKit

extension AppModel {
    func loadConnectionRegistry() {
        connectionRegistry = PairedConnectionStore.load()
        pairing = connectionRegistry.preferred?.pairing
        pruneSessionSourceRoomsToLinkedRooms()
    }

    func persistConnectionRegistry() {
        _ = PairedConnectionStore.save(connectionRegistry)
        pairing = connectionRegistry.preferred?.pairing
    }

    /// Add or refresh one computer. Default mode never wipes other links.
    @discardableResult
    func addConnection(_ p: Pairing, mode: PairAddMode = .add,
                       prefer: Bool = true) -> Bool {
        guard Pairing.isValid(p) else {
            append(Self.pairingStorageFailureMessage)
            return false
        }
        let previousRegistry = connectionRegistry
        let previousPairing = pairing
        let previousPreferredId = connectionRegistry.preferredId
        let previousPreferredPeer = connectionRegistry.preferred?.pairing.peerPublicKey
        let nextRegistry = ConnectionRegistryLogic.upsert(
            connectionRegistry, pairing: p, mode: mode, prefer: prefer
        )
        // Persist the complete candidate before publishing or clearing any
        // catalog state. Keychain failure must leave the current link usable and
        // must not create a connection that exists only until process death.
        guard PairedConnectionStore.save(nextRegistry) else {
            connectionRegistry = previousRegistry
            pairing = previousPairing
            append(Self.pairingStorageFailureMessage)
            return false
        }

        connectionRegistry = nextRegistry
        pairing = nextRegistry.preferred?.pairing
        // Pairing after Explore Demo used to flip demoMode=false while leaving
        // granttap-*-demo rows (Cloudflare MCP fixture, etc.) in Active forever.
        purgeDemoCatalogResidue(reason: "pair")
        let preferredChanged = previousPreferredId != nextRegistry.preferredId
            || previousPreferredPeer != nextRegistry.preferred?.pairing.peerPublicKey
        if preferredChanged {
            clearRemoteCatalogForPreferSwitch(reason: "pair-\(p.room.prefix(8))")
        } else {
            pruneSessionSourceRoomsToLinkedRooms()
        }
        AuditStore.shared.record("pairing", detail: "Linked \(p.deviceName) · room \(p.room.prefix(8))")
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["GRANTTAP_E2E_ACCEPT_PAIRING"] != "1" {
            NotificationManager.shared.requestAuthorization()
        }
        #else
        NotificationManager.shared.requestAuthorization()
        #endif
        restartAllRelays()
        PushRegistrationManager.shared.pairingDidChange()
        return true
    }

    func unlinkConnection(roomId: String) {
        let wasPreferred = connectionRegistry.preferredId == roomId
        let removedRequestIds = Set(
            requestSourceRoom.compactMap { $0.value == roomId ? $0.key : nil }
        )
        pending.removeAll { removedRequestIds.contains($0.requestId) }
        questions.removeAll { event in
            event.requestId.map(removedRequestIds.contains) ?? false
        }
        for requestId in removedRequestIds {
            approvalDecisionsInFlight[requestId] = nil
            approvalDecisionSessionScope[requestId] = nil
            NotificationManager.shared.clear(requestId)
        }
        if let focusedApprovalId, removedRequestIds.contains(focusedApprovalId) {
            self.focusedApprovalId = nil
        }
        let now = Date().timeIntervalSince1970 * 1000
        for index in deliveries.indices where deliveries[index].roomId == roomId
            && deliveries[index].state != .delivered {
            if let generation = deliveries[index].attemptGeneration {
                liveDeliveryAttemptGenerations.remove(generation)
            }
            deliveries[index].state = .failed
            deliveries[index].updatedAt = now
            deliveries[index].nextRetryAt = nil
            deliveries[index].processingAcknowledgedAt = nil
            deliveries[index].processingRetryStartedAt = nil
            deliveries[index].attemptGeneration = nil
            deliveries[index].error = L("The source computer for this message was removed.")
        }
        persistDeliveries()
        if let conn = connectionRegistry.connections.first(where: { $0.id == roomId }) {
            PushRegistrationManager.shared.unregister(conn.pairing)
            SessionKeyVault.remove(room: roomId)
            AuditStore.shared.record("pairing", detail: "Unlinked \(conn.displayName)")
        }
        relaysByRoom[roomId]?.disconnect()
        relaysByRoom[roomId] = nil
        roomRuntime[roomId] = nil
        // Keep request→room tombstones: any still-visible card must fail closed
        // instead of falling through to a different linked computer.
        connectionRegistry = ConnectionRegistryLogic.remove(connectionRegistry, roomId: roomId)
        persistConnectionRegistry()
        if connectionRegistry.connections.isEmpty {
            clearLinkLocalState()
        } else {
            if wasPreferred {
                clearRemoteCatalogForPreferSwitch(reason: "unlink-\(roomId.prefix(8))")
            } else {
                pruneSessionSourceRoomsToLinkedRooms()
            }
            restartAllRelays()
        }
        pushToWatch()
    }

    func setPreferredConnection(roomId: String) {
        let previous = connectionRegistry.preferredId
        guard let next = ConnectionRegistryLogic.setPreferred(connectionRegistry, roomId: roomId) else {
            return
        }
        connectionRegistry = next
        persistConnectionRegistry()
        // Drop stale Active/SQLite from the previous Prefer-for-chats room so
        // code-blob / foreign ghosts cannot linger until the new Mac publishes.
        if previous != roomId {
            clearRemoteCatalogForPreferSwitch(reason: "prefer-\(roomId.prefix(8))")
        }
        // Preferred owns catalog — rebind `relay` without dropping other sockets.
        relay = relaysByRoom[roomId]
        if let client = relay, client.task != nil {
            nudgeMacSessionScan(via: client)
        }
        objectWillChange.send()
        pushToWatch()
    }

    /// Wipe state owned by the previous preferred room. Approval cards remain
    /// room-scoped and actionable, but chat/activity aliases never cross rooms.
    func clearRemoteCatalogForPreferSwitch(reason: String) {
        sessions = []
        sessionHistory = []
        activities = [:]
        for task in activityHeartbeatTasks.values { task.cancel() }
        activityHeartbeatTasks = [:]
        activitySubscribers = [:]
        sessionIdAliases = [:]
        persistSessionIdAliases()
        sessionToOpen = nil
        // Keep only stubs referenced by persisted, room-pinned outbox rows so a
        // retry cannot accidentally put a phone UUID on the wire.
        let deliverySessionIds = Set(deliveries.compactMap(\.sessionId))
        localOnlySessionIds.formIntersection(deliverySessionIds)
        persistLocalOnlySessions()
        resetSessionSourceRoomsForCatalogSwitch()
        lastSessionsGeneratedAt = 0
        machineName = ""
        agentIntegrations = []
        tokensRecent = 0
        tokenWindowHours = 12
        gatingEnabled = true
        excludedSessions = []
        autoAcceptDefault = "except_push"
        autoAcceptBySession = [:]
        autoAcceptPaused = false
        compactingSessions = []
        compactResults = [:]
        SessionCatalogCache.clear()
        append("catalog-isolation: cleared for prefer switch (\(reason))")
    }

    func reconnectConnection(
        roomId: String, delayNanoseconds: UInt64 = 1_200_000_000
    ) async {
        if let client = relaysByRoom[roomId] {
            client.forceReconnect()
        } else if let conn = connectionRegistry.connections.first(where: { $0.id == roomId }) {
            attachRelay(for: conn.pairing)
        }
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        if roomId == connectionRegistry.preferredId, let relay, connected {
            nudgeMacSessionScan(via: relay)
        }
    }

    func restartAllRelays() {
        for client in relaysByRoom.values { client.disconnect() }
        relaysByRoom.removeAll()
        roomRuntime.removeAll()
        relay = nil
        connected = false
        guard !connectionRegistry.connections.isEmpty else { return }
        for conn in connectionRegistry.connections {
            attachRelay(for: conn.pairing)
        }
        relay = connectionRegistry.preferredId.flatMap { relaysByRoom[$0] }
            ?? relaysByRoom.values.first
        pruneStaleDeliveries()
    }
}
