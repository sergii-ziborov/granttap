import Foundation
import SwiftUI

extension AppModel {
    /// One visible route per MCP computer; QR and passkey rooms of the same
    /// verified machine remain one list item.
    var connectionOverview: [LinkedComputer] {
        let rooms = accountVisibleRooms()
        return connectionRegistry.connections.filter { rooms.contains($0.id) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// Account status reflects any publishing MCP device, not a default route.
    var connectionSnapshot: ConnectionSnapshot {
        if demoMode {
            return ConnectionSnapshot(
                phase: .demo,
                linked: false,
                deviceName: nil,
                machineName: machineName.isEmpty ? nil : machineName,
                roomShort: nil,
                catalogAgeSeconds: nil
            )
        }
        guard let preferred = connectionRegistry.preferred else {
            return ConnectionSnapshot(
                phase: .notLinked,
                linked: false,
                deviceName: nil,
                machineName: nil,
                roomShort: nil,
                catalogAgeSeconds: nil
            )
        }
        let visibleRooms = accountVisibleRooms()
        if let live = connectionRegistry.connections.first(where: {
            visibleRooms.contains($0.id) && snapshotForConnection($0).phase == .live
        }) {
            return snapshotForConnection(live)
        }
        if let checking = connectionRegistry.connections.first(where: {
            visibleRooms.contains($0.id) && snapshotForConnection($0).phase == .connecting
        }) { return snapshotForConnection(checking) }
        return snapshotForConnection(preferred)
    }

    /// The header answers whether this device reached the relay. Computer health stays in its own rows.
    var relayConnectionSnapshot: ConnectionSnapshot {
        let snapshot = connectionSnapshot
        guard !demoMode, snapshot.linked else { return snapshot }
        let visible = accountVisibleRooms()
        let routes = roomRuntime.filter { visible.contains($0.key) }.map(\.value)
        let now = Date().timeIntervalSince1970 * 1_000
        let phase: ConnectionPhase = routes.contains(where: \.socketUp) ? .live
            : routes.contains { $0.connectingSince > 0 && now - $0.connectingSince < ConnectionFreshness.connectionWindowMs }
                ? .connecting : .phoneOffline
        return ConnectionSnapshot(phase: phase, linked: true, deviceName: snapshot.deviceName,
            machineName: nil, roomShort: nil, catalogAgeSeconds: snapshot.catalogAgeSeconds)
    }

    var isMacCatalogFresh: Bool {
        guard lastSessionsGeneratedAt > 0 else { return false }
        let ageMs = Date().timeIntervalSince1970 * 1000 - lastSessionsGeneratedAt
        return ageMs >= 0 && ageMs < ConnectionSnapshot.macFreshnessSeconds * 1000
    }

    var catalogAgeSeconds: Int? {
        guard lastSessionsGeneratedAt > 0 else { return nil }
        let ageMs = Date().timeIntervalSince1970 * 1000 - lastSessionsGeneratedAt
        guard ageMs >= 0 else { return 0 }
        return Int(ageMs / 1000)
    }

    var needsForegroundCatalogRecovery: Bool {
        !demoMode && ConnectionSnapshot.shouldRecoverCatalogLink(
            for: connectionSnapshot.phase
        )
    }

    func recoverCatalogAfterForeground(startIfNeeded: (() -> Void)? = nil) {
        guard needsForegroundCatalogRecovery else { return }
        refreshAfterConnect = true
        let client = connectionRegistry.preferredId.flatMap { relaysByRoom[$0] } ?? relay
        if let client {
            beginConnectionCheck(room: client.pairing.room)
            client.forceReconnect(requestPeerRecovery: true)
        } else if let startIfNeeded {
            startIfNeeded()
        } else {
            start()
        }
    }

    /// Repair one specific computer from its own row.
    ///
    /// `fixConnection` only ever repaired the preferred computer, so a second
    /// linked Mac could be shown as offline with no way to act on it.
    func repairConnection(
        roomId: String,
        reconnect: ((String) async -> Void)? = nil
    ) async {
        setRefreshHint(L("Reconnecting…"))
        beginConnectionCheck(room: roomId)
        refreshAfterConnect = true
        if let reconnect {
            await reconnect(roomId)
        } else {
            await reconnectConnection(roomId: roomId)
        }
        if roomId == connectionRegistry.preferredId, connected {
            setRefreshHint(L("Phone linked — waiting for Mac…"))
        }
    }

    /// A bounded check prevents cached state being presented as a new outage.
    func beginConnectionCheck(room: String) {
        let started = Date().timeIntervalSince1970 * 1_000
        var state = roomRuntime[room] ?? RoomRuntime()
        state.connectingSince = started
        objectWillChange.send()
        roomRuntime[room] = state
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ConnectionFreshness.connectionWindowMs * 1_000_000))
            guard self?.roomRuntime[room]?.connectingSince == started else { return }
            self?.objectWillChange.send()
        }
    }

    /// Preferred-computer recovery (home / legacy Fix connection).
    func fixConnection(
        reconnect: ((String) async -> Void)? = nil,
        wait: (() async -> Void)? = nil,
        refresh: (() async -> Void)? = nil
    ) async {
        switch connectionSnapshot.phase {
        case .demo:
            stopDemo()
        case .notLinked, .needRepair:
            break
        case .connecting, .phoneOffline:
            setRefreshHint(L("Reconnecting…"))
            refreshAfterConnect = true
            if let id = connectionRegistry.preferredId {
                beginConnectionCheck(room: id)
                if let reconnect { await reconnect(id) }
                else { await reconnectConnection(roomId: id) }
            } else if let relay {
                relay.forceReconnect()
            } else if pairing != nil {
                start()
            }
            if let wait { await wait() }
            else { try? await Task.sleep(nanoseconds: 200_000_000) }
            if connected {
                if let relay { nudgeMacSessionScan(via: relay) }
                setRefreshHint(L("Phone linked — waiting for Mac…"))
            } else {
                setRefreshHint(L("Still offline"))
            }
        case .macOffline, .live:
            if let refresh { await refresh() }
            else { await refreshSessions() }
        }
    }
}
