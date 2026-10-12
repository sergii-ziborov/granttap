import Foundation

/// One account can have many MCP machines. Their encrypted device routes stay
/// separate, while their published Tasks form one visible account catalog.
@MainActor
enum AccountDeviceCatalog {
    /// A QR room and a passkey room are routes of the same MCP computer once
    /// both have the server-verified machine identity. Keep unverified rooms
    /// visible as connections until their identity can be established.
    static func otherConnections(in registry: ConnectionRegistry, accountId: String?,
                                 machineIds: Set<String>) -> [LinkedComputer] {
        registry.connections.filter { connection in
            guard !connection.pairing.isHub,
                  connection.linkedAccountId == accountId,
                  let machineId = connection.linkedMachineId else { return true }
            return !machineIds.contains(machineId)
        }
    }

    static func rooms(in registry: ConnectionRegistry, accountId: String?,
                      liveRooms: Set<String> = []) -> Set<String> {
        let allowed = registry.connections.filter { connection in
            guard !connection.pairing.isHub else { return false }
            guard let accountId else {
                return connection.accountReference == nil || connection.accountCredential != nil
            }
            return connection.linkedAccountId == nil || connection.linkedAccountId == accountId
        }
        let facets = Dictionary(grouping: allowed) { $0.linkedMachineId ?? $0.id }
        return Set(facets.values.compactMap { routes in
            routes.max { first, second in
                let firstReported = first.lastCatalogAt > 0
                let secondReported = second.lastCatalogAt > 0
                if firstReported != secondReported { return !firstReported }
                let firstLive = liveRooms.contains(first.id)
                let secondLive = liveRooms.contains(second.id)
                if firstLive != secondLive { return !firstLive }
                if first.lastCatalogAt != second.lastCatalogAt {
                    return first.lastCatalogAt < second.lastCatalogAt
                }
                if first.lastRecoveredAt != second.lastRecoveredAt {
                    return (first.lastRecoveredAt ?? 0) < (second.lastRecoveredAt ?? 0)
                }
                return first.addedAt < second.addedAt
            }?.id
        })
    }

    static func combined(_ catalogs: [String: SessionsStatus], rooms: Set<String>)
        -> (live: [SessionInfo], history: [SessionInfo]) {
        let reports = rooms.sorted().compactMap { catalogs[$0] }
        let live = AppModel.deduplicatedSessions(reports.flatMap(\.sessions))
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
        let liveIds = Set(live.map(\.sessionId))
        let history = AppModel.deduplicatedSessions(reports.flatMap { $0.history ?? [] })
            .filter { !liveIds.contains($0.sessionId) }
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
        return (live, history)
    }
}

@MainActor
extension AppModel {
    func accountVisibleRooms() -> Set<String> {
        let live = Set(roomRuntime.compactMap { $0.value.socketUp ? $0.key : nil })
        return AccountDeviceCatalog.rooms(in: connectionRegistry,
            accountId: GrantTapAccountAPI.session?.accountId, liveRooms: live)
    }

    func captureAccountDeviceCatalog(_ status: SessionsStatus, fromRoom room: String) {
        guard connectionRegistry.connections.contains(where: { $0.id == room }) else { return }
        let previous = accountDeviceCatalogs[room]
        let previousRows = (previous?.sessions ?? []) + (previous?.history ?? [])
        func prepare(_ rows: [SessionInfo]) -> [SessionInfo] {
            Self.filterRealCatalogSessions(Self.deduplicatedSessions(rows), allowDemo: false)
                .map { row in
                    let old = previousRows.first {
                        $0.sessionId == row.sessionId && $0.agent == row.agent
                            && $0.computerId == row.computerId
                            && $0.projectId == row.projectId && $0.taskId == row.taskId
                    }
                    return Self.retainingCapabilities(incoming: row, previous: old)
                }
        }
        var clean = status
        clean.sessions = prepare(status.sessions)
        clean.history = status.history.map(prepare) ?? previous?.history
        accountDeviceCatalogs[room] = clean
        resumeChatQueues(observed: clean.sessions + (clean.history ?? []), fromRoom: room)
    }

    func accountVisibleCatalog() -> (live: [SessionInfo], history: [SessionInfo]) {
        AccountDeviceCatalog.combined(accountDeviceCatalogs,
            rooms: accountVisibleRooms())
    }

    func refreshAccountDeviceCatalog() {
        let visible = accountVisibleCatalog()
        if visible.live.isEmpty && visible.history.isEmpty {
            loadCachedSessionCatalogIfNeeded()
            preloadActiveSessionEvents(sessions)
            return
        }
        let stubs = sessions.filter { localOnlySessionIds.contains($0.sessionId) }
        let previous = sessions + sessionHistory
        sessions = Self.deduplicatedSessions(visible.live + stubs).map { incoming in
            let saved = previous.first { $0.sessionId == incoming.sessionId && $0.agent == incoming.agent
                && $0.computerId == incoming.computerId }
            return Self.retainingCapabilities(incoming: incoming, previous: saved)
        }
        let liveIds = Set(sessions.map(\.sessionId))
        sessionHistory = visible.history.filter { !liveIds.contains($0.sessionId) }
        if visible.live.isEmpty && visible.history.isEmpty {
            SessionCatalogCache.clear()
        } else {
            SessionCatalogCache.save(.init(
                sessions: sessions, history: sessionHistory, machine: machineName,
                tokensRecent: tokensRecent, tokenWindowHours: tokenWindowHours,
                generatedAt: lastSessionsGeneratedAt
            ))
        }
        preloadActiveSessionEvents(sessions)
        objectWillChange.send()
        pushToWatch()
    }
}
