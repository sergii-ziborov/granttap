import Foundation
import SwiftUI
import UIKit

extension AppModel {
    func applySessionsStatus(_ status: SessionsStatus, fromRoom room: String) {
        if let current = connectionRegistry.connections.first(where: { $0.id == room }),
           current.lastCatalogAt > 0,
           status.generatedAt < current.lastCatalogAt {
            append("sessions.status stale snapshot ignored")
            return
        }
        rememberSessionSourceRooms(
            room,
            sessionIds: status.sessions.map(\.sessionId)
                + (status.history ?? []).map(\.sessionId)
        )
        connectionRegistry = ConnectionRegistryLogic.noteCatalog(
            connectionRegistry,
            roomId: room,
            generatedAt: status.generatedAt,
            machineName: status.machine
        )
        _ = PairedConnectionStore.save(connectionRegistry)
        pairing = connectionRegistry.preferred?.pairing

        let preferred = connectionRegistry.preferredId
        if preferred == nil || preferred == room {
            applySessionsStatus(status, sourceNamespace: room)
        } else {
            // Secondary Mac publishing — health only; do not clobber active catalog.
            // If preferred is dead, strip code-blob ghosts so Active is not a lie.
            purgeStalePreferredCatalogIfNeeded()
            objectWillChange.send()
            finishBackgroundWake(.newData)
        }
    }

    /// Liveness evidence, kept separate from catalog content on purpose: the
    /// machine may legitimately need minutes to rebuild a large catalog, and a
    /// slow catalog used to read as a dead computer and wipe the chat list.
    func noteMachineHeartbeat(_ beat: MachineHeartbeat, fromRoom room: String) {
        var runtime = roomRuntime[room] ?? RoomRuntime()
        // Trust arrival time, not the sender's clock — a skewed Mac must not be
        // able to claim liveness further into the future than it really is.
        runtime.lastHeartbeatAt = Date().timeIntervalSince1970 * 1_000
        roomRuntime[room] = runtime
        append("link \(String(room.prefix(8)))… Mac heartbeat")
        let machine = beat.machine.trimmingCharacters(in: .whitespacesAndNewlines)
        if room == connectionRegistry.preferredId, !machine.isEmpty, machineName.isEmpty {
            machineName = machine
        }
        objectWillChange.send()
    }

    /// Resolve the immutable computer route shown by the composer and outbox.
    /// Existing chats require exact ownership; only a single-room legacy state
    /// may be migrated. New tasks use the user's explicit preferred computer.
    func chatComputerRoute(forSessionId sessionId: String?) -> ChatComputerRoute? {
        let room: String
        if let raw = sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            switch sessionRoomOwnership(forSessionId: raw) {
            case .exact(let exactRoom):
                room = exactRoom
            case .ambiguous:
                return nil
            case .unknown:
                guard connectionRegistry.connections.count == 1,
                      let only = connectionRegistry.connections.first else { return nil }
                room = only.id
            }
        } else {
            guard let preferred = connectionRegistry.preferred else { return nil }
            room = preferred.id
        }
        guard let connection = connectionRegistry.connections.first(where: { $0.id == room }) else {
            return nil
        }
        let machine = connection.lastMachineName.trimmingCharacters(in: .whitespacesAndNewlines)
        return ChatComputerRoute(
            roomId: room,
            computerName: machine.isEmpty ? connection.displayName : machine,
            phase: snapshotForConnection(connection).phase
        )
    }

    func chatComputerRoute(forRoomId roomId: String?) -> ChatComputerRoute? {
        guard let room = roomId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !room.isEmpty,
              let connection = connectionRegistry.connections.first(where: { $0.id == room })
        else { return nil }
        let machine = connection.lastMachineName.trimmingCharacters(in: .whitespacesAndNewlines)
        return ChatComputerRoute(
            roomId: room,
            computerName: machine.isEmpty ? connection.displayName : machine,
            phase: snapshotForConnection(connection).phase
        )
    }

    /// Preferred room not Live → drop undecryptable/foreign Active rows (keep local stubs).
    func purgeStalePreferredCatalogIfNeeded() {
        let phase = connectionSnapshot.phase
        guard phase == .macOffline || phase == .needRepair else { return }
        let before = sessions.count + sessionHistory.count
        sessions = sessions.filter {
            localOnlySessionIds.contains($0.sessionId)
                && !Self.isGrantTapDemoSessionId($0.sessionId)
                && !Self.isCodeBlobCatalogTitle(sessionId: $0.sessionId, title: $0.title)
        }
        sessionHistory = Self.filterRealCatalogSessions(sessionHistory, allowDemo: false)
            .filter { !Self.isCodeBlobCatalogTitle(sessionId: $0.sessionId, title: $0.title) }
        // History from a dead preferred room is also stale — clear it.
        if phase == .needRepair || !isMacCatalogFresh {
            sessionHistory = []
            SessionCatalogCache.clear()
        }
        let after = sessions.count + sessionHistory.count
        if before != after {
            append("catalog-isolation: purged stale preferred ghosts \(before)→\(after)")
            objectWillChange.send()
            pushToWatch()
        }
    }

    func relayForRequest(_ requestId: String) -> RelayClient? {
        if let room = requestSourceRoom[requestId] {
            // Known source removed/offline: fail closed, never fall through to a
            // different computer's preferred relay.
            return relaysByRoom[room]
        }
        // Migration path for notifications created before room pinning: safe only
        // when exactly one linked room exists.
        guard connectionRegistry.connections.count == 1,
              let room = connectionRegistry.connections.first?.id else { return nil }
        rememberRequestSourceRoom(room, requestId: requestId)
        return relaysByRoom[room]
    }

    func clearRequestRooms(for roomId: String) {
        requestSourceRoom = requestSourceRoom.filter { $0.value != roomId }
        UserDefaults.standard.set(requestSourceRoom, forKey: "granttap.request-source-rooms")
        clearApprovalConvergenceState(forRoom: roomId)
    }

    func clearLinkLocalState() {
        relay?.disconnect()
        for client in relaysByRoom.values { client.disconnect() }
        relaysByRoom.removeAll()
        roomRuntime.removeAll()
        requestSourceRoom.removeAll()
        UserDefaults.standard.removeObject(forKey: "granttap.request-source-rooms")
        clearApprovalConvergenceState()
        sessionSourceRooms.removeAll()
        UserDefaults.standard.removeObject(forKey: "granttap.session-source-rooms")
        relay = nil
        pairing = nil
        connectionRegistry = .empty
        demoMode = false
        connected = false
        pending = []
        approvalDecisionsInFlight = [:]
        approvalDecisionSessionScope = [:]
        questions = []
        log = []
        sessions = []
        sessionHistory = []
        activities = [:]
        sessionIdAliases = [:]
        localOnlySessionIds = []
        UserDefaults.standard.removeObject(forKey: "granttap.session-id-aliases")
        UserDefaults.standard.removeObject(forKey: "granttap.local-only-sessions")
        compactingSessions = []
        compactResults = [:]
        tokensRecent = 0
        machineName = ""
        excludedSessions = []
        autoAcceptDefault = "except_push"
        autoAcceptBySession = [:]
        autoAcceptByProject = [:]
        autoAcceptPaused = false
        deliveries = []
        liveDeliveryAttemptGenerations = []
        archivedSessionIds = []
        archivedSessions = [:]
        DeliveryPersistence.remove()
        ArchivedSessionPersistence.remove()
        SessionCatalogCache.clear()
        persistArchivedSessions()
        for task in activityHeartbeatTasks.values { task.cancel() }
        activityHeartbeatTasks = [:]
        activitySubscribers = [:]
    }

    func snapshotForConnection(_ conn: LinkedComputer) -> ConnectionSnapshot {
        let rt = roomRuntime[conn.id] ?? RoomRuntime()
        let catalogAt = conn.lastCatalogAt
        let now = Date().timeIntervalSince1970 * 1000
        let age: Int? = catalogAt > 0 ? Int(max(0, (now - catalogAt) / 1000)) : nil
        // A slow catalog is not a dead computer. Either kind of evidence proves
        // the publisher is alive; both must be inside the freshness window, so
        // a computer that truly went away still fails closed.
        let window = ConnectionSnapshot.macFreshnessSeconds * 1000
        let catalogFresh = catalogAt > 0 && (now - catalogAt) < window
        let heartbeatFresh = rt.lastHeartbeatAt > 0 && (now - rt.lastHeartbeatAt) < window
        let fresh = catalogFresh || heartbeatFresh
        let phase: ConnectionPhase
        if !rt.socketUp {
            phase = .phoneOffline
        } else if fresh {
            phase = .live
        } else if catalogAt <= 0, rt.socketUpSince > 0,
                  now - rt.socketUpSince >= 180_000 {
            phase = .needRepair
        } else {
            phase = .macOffline
        }
        let room = conn.id
        let short = room.count > 10 ? String(room.prefix(8)) + "…" : room
        return ConnectionSnapshot(
            phase: phase,
            linked: true,
            deviceName: conn.displayName,
            machineName: conn.lastMachineName.isEmpty ? nil : conn.lastMachineName,
            roomShort: short,
            catalogAgeSeconds: age
        )
    }
}
