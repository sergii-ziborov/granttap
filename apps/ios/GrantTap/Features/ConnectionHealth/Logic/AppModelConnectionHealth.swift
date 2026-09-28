import Foundation
import SwiftUI

extension AppModel {
    /// Aggregate status for the home header pill (preferred computer).
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
        return snapshotForConnection(preferred)
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
        case .phoneOffline:
            setRefreshHint(L("Reconnecting…"))
            refreshAfterConnect = true
            if let id = connectionRegistry.preferredId {
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
