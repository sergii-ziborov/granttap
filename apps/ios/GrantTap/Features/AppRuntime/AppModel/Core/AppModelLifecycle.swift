import Foundation
import UIKit

@MainActor
extension AppModel {
    func start() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["GRANTTAP_TEST_CONNECTION_LIST"] == "1" {
            ConnectionListFixture.apply(to: self)
            return
        }
        if ProcessInfo.processInfo.environment["GRANTTAP_TEST_INVITE_SCOPES"] != nil {
            InviteScopeFixture.apply(to: self)
            return
        }
        if ProcessInfo.processInfo.environment["GRANTTAP_DEMO"] == "1" {
            // Demo must not activate WCSession. On Simulator it can starve UI work.
            startDemo()
            return
        }
        #endif
        WatchBridge.shared.start()
        restoreLocalReplica()
        startAccountSpaceSync()
        if !demoMode,
           sessions.contains(where: { Self.isGrantTapDemoSessionId($0.sessionId) })
            || sessionHistory.contains(where: { Self.isGrantTapDemoSessionId($0.sessionId) }) {
            purgeDemoCatalogResidue(reason: "start")
        }
        pushToWatch(force: true)
        startGrokBotEndpointIfNeeded()
        attachStoredMemberLinks()
        if !connectionRegistry.connections.isEmpty {
            NotificationManager.shared.requestAuthorization()
        }
        guard !connectionRegistry.connections.isEmpty else { return }
        restartAllRelays()
        resumeRelayTaskQueues()
        PushRegistrationManager.shared.pairingDidChange()
    }

    /// Debounce Offline so Connected does not blink on every WebSocket blip.
    func applyConnectionChange(
        _ up: Bool,
        client: RelayClient,
        disconnectDelayNanoseconds: UInt64 = 1_800_000_000
    ) {
        connectedDebounceTask?.cancel()
        if up {
            connected = true
            refreshAfterConnect = false
            nudgeMacSessionScan(via: client)
            retryQueuedDeliveries()
            objectWillChange.send()
            pushToWatch()
            return
        }
        connectedDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: disconnectDelayNanoseconds)
            guard !Task.isCancelled,
                  !self.roomRuntime.values.contains(where: \.socketUp) else { return }
            self.connected = false
            self.objectWillChange.send()
            self.pushToWatch()
        }
    }

    /// Unlink every computer from this phone without changing the remote runtime.
    func forgetPairing() {
        for connection in connectionRegistry.connections {
            PushRegistrationManager.shared.unregister(connection.pairing)
        }
        AuditStore.shared.record("pairing", detail: "All linked computers removed")
        PairedConnectionStore.removeAll()
        clearLinkLocalState()
        pushToWatch()
    }
}
