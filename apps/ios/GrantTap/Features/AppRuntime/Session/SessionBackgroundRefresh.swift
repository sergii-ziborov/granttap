import Foundation
import SwiftUI
import UIKit

extension AppModel {
    func handleRemoteWake(completion: @escaping (UIBackgroundFetchResult) -> Void) {
        let id = UUID()
        backgroundWakeCompletions[id] = completion
        AuditStore.shared.record("push", detail: "APNs wake received")
        // Wake every linked room — asks may wait on a non-preferred Mac/PC.
        if relaysByRoom.isEmpty {
            relay?.wakeForRemoteNotification()
        } else {
            for client in relaysByRoom.values { client.wakeForRemoteNotification() }
        }
        // APNs wake → WS reconnect → decrypt can exceed 8s on cellular.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, let completion = self.backgroundWakeCompletions.removeValue(forKey: id) else { return }
            completion(.noData)
        }
    }

    func finishBackgroundWake(_ result: UIBackgroundFetchResult) {
        let callbacks = backgroundWakeCompletions.values
        backgroundWakeCompletions.removeAll()
        callbacks.forEach { $0(result) }
    }

    /// Drop a stored empty transcript so Retry can show the spinner again
    /// until the next Mac snapshot arrives.
    func clearEmptyActivitySnapshot(sessionId: String) {
        let id = resolvedSessionId(sessionId)
        var next = activities
        var changed = false
        for key in [id, sessionId] where next[key]?.entries.isEmpty == true {
            next.removeValue(forKey: key)
            changed = true
        }
        guard changed else { return }
        activities = next
    }

    static let threadEventRequestIntervalMs: Double = 20_000
    static let sessionPreloadIntervalMs: Double = 30_000

    /// Load every live chat while its catalog is active. Opening a screen then
    /// reads the already decrypted cache instead of starting the first fetch.
    func preloadActiveSessionEvents(
        _ sessions: [SessionInfo], now: Double = Date().timeIntervalSince1970 * 1_000
    ) {
        let liveIds = Set(sessions.map { resolvedSessionId($0.sessionId) })
        let retiredIds = Set(sessionEventRequestsAt.keys).subtracting(liveIds)
        for id in retiredIds {
            relayForSession(id)?.sendSubscription(sessionId: id, active: false)
        }
        sessionEventRequestsAt = sessionEventRequestsAt.filter { liveIds.contains($0.key) }
        for id in liveIds {
            guard let sourceRelay = relayForSession(id), let room = roomId(for: sourceRelay),
                  roomRuntime[room]?.socketUp == true else { continue }
            if let last = sessionEventRequestsAt[id], now - last < Self.sessionPreloadIntervalMs {
                continue
            }
            sessionEventRequestsAt[id] = now
            sourceRelay.sendSubscription(sessionId: id, active: true)
        }
        // The bounded queue fetches current heads before older pages. Sending a
        // second full-history request here flooded all chats at each catalog tick.
        syncOfflineConversations(now: now)
    }

    /// Ask the computer for one agent conversation, whole. The chat's own
    /// window keeps only a few rows of each conversation; opened, it is read
    /// from the transcript and merged into what the phone already holds.
    func requestThreadEvents(_ sessionId: String, threadId: String,
                             now: Double = Date().timeIntervalSince1970 * 1_000) {
        let id = resolvedSessionId(sessionId)
        let key = "\(id)\u{1f}\(threadId)"
        if let last = threadEventRequestsAt[key], now - last < Self.threadEventRequestIntervalMs { return }
        threadEventRequestsAt[key] = now
        relayForSession(id)?.requestSessionEvents(sessionId: id, threadId: threadId)
    }

    func subscribeSession(
        _ sessionId: String, active: Bool, source: String,
        preserveRemoteSubscription: Bool = false
    ) {
        // Always subscribe to the Mac id after stub remap (live chat ticks).
        let id = resolvedSessionId(sessionId)
        var sources = activitySubscribers[id] ?? []
        let wasActive = !sources.isEmpty
        if active { sources.insert(source) } else { sources.remove(source) }
        if sources.isEmpty { activitySubscribers.removeValue(forKey: id) }
        else { activitySubscribers[id] = sources }
        let isActive = !sources.isEmpty
        // Every open is also a one-shot fetch. This repairs a stale local
        // subscription after the Mac monitor restarts while the phone stays up.
        let sourceRelay = relayForSession(id)
        if active {
            sourceRelay?.sendSubscription(sessionId: id, active: true)
            sourceRelay?.requestSessionEvents(sessionId: id)
            startActivityHeartbeat(id)
        }
        if wasActive != isActive {
            if !isActive {
                stopActivityHeartbeat(id)
                if !preserveRemoteSubscription && !sessions.contains(where: { resolvedSessionId($0.sessionId) == id }) {
                    sourceRelay?.sendSubscription(sessionId: id, active: false)
                }
            }
            // Never wipe a loaded transcript on unsubscribe — that caused the
            // infinite "Opening the encrypted…" spinner when navigating to
            // Full chat or briefly dismissing the sheet.
            pushToWatch()
        }
    }

    /// While a chat is open, re-request events so live Cursor/Claude turns append
    /// even if an embedded preview tick was dropped or decode-stripped.
    func startActivityHeartbeat(_ sessionId: String) {
        activityHeartbeatTasks[sessionId]?.cancel()
        activityHeartbeatTasks[sessionId] = Task { @MainActor in
            // First refresh soon, then slow down — 2.5s forever flickered the chat.
            var interval: UInt64 = 3_000_000_000
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled else { return }
                guard activitySubscribers[sessionId]?.isEmpty == false else { return }
                guard connected else {
                    // Stay idle while offline — never tight-loop the MainActor.
                    interval = 6_000_000_000
                    continue
                }
                let sourceRelay = relayForSession(sessionId)
                sourceRelay?.sendSubscription(sessionId: sessionId, active: true)
                sourceRelay?.requestSessionEvents(sessionId: sessionId)
                interval = 6_000_000_000
            }
        }
    }

    func stopActivityHeartbeat(_ sessionId: String) {
        activityHeartbeatTasks[sessionId]?.cancel()
        activityHeartbeatTasks.removeValue(forKey: sessionId)
    }

    /// Pull-to-refresh asks every MCP facet of this account for its catalog.
    func refreshSessions() async {
        guard !demoMode else {
            try? await Task.sleep(nanoseconds: 350_000_000)
            return
        }
        let rooms = accountVisibleRooms()
        let routes = rooms.sorted().compactMap { room in
            relaysByRoom[room].map { (room, $0) }
        }
        guard !routes.isEmpty else {
            setRefreshHint(L("Not paired"))
            return
        }
        let stamp = lastSessionsGeneratedAt
        setRefreshHint(L("Updating chats…"))
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let id = UUID()
            sessionRefreshWaiters[id] = continuation
            for (room, client) in routes {
                if roomRuntime[room]?.socketUp == true {
                    nudgeMacSessionScan(via: client)
                } else {
                    refreshAfterConnect = true
                    client.forceReconnect(requestPeerRecovery: true)
                }
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                completeSessionRefresh(id)
            }
        }
        if lastSessionsGeneratedAt != stamp {
            let n = sessions.count
            setRefreshHint(String(format: L("Updated · %d active"), n))
        } else if roomRuntime.values.contains(where: \.socketUp) {
            setRefreshHint(L("No update from Mac — is granttap monitor running?"))
        } else {
            setRefreshHint(L("Still offline"))
        }
    }

    /// New monitors honor sessions.refresh; older ones republish on config.set.
    func nudgeMacSessionScan(via client: RelayClient) {
        client.requestSessionsRefresh()
        client.sendConfig(enabled: gatingEnabled)
        let targetRoom = roomId(for: client)
        for sessionId in activitySubscribers.keys {
            switch sessionRoomOwnership(forSessionId: sessionId) {
            case .exact(let owner):
                if let targetRoom, owner != targetRoom { continue }
            case .ambiguous:
                continue
            case .unknown:
                guard connectionRegistry.connections.count == 1,
                      targetRoom == connectionRegistry.connections.first?.id else { continue }
            }
            client.sendSubscription(sessionId: sessionId, active: true)
            client.requestSessionEvents(sessionId: sessionId)
        }
    }

    func setRefreshHint(_ text: String?) {
        refreshHintClearTask?.cancel()
        refreshHint = text
        guard text != nil else { return }
        refreshHintClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            refreshHint = nil
        }
    }

    func completeSessionRefresh(_ id: UUID) {
        sessionRefreshWaiters.removeValue(forKey: id)?.resume()
    }

    func completeSessionRefreshWaiters() {
        let waiters = sessionRefreshWaiters
        sessionRefreshWaiters.removeAll()
        for (_, continuation) in waiters { continuation.resume() }
    }
}
