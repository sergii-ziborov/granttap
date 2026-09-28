#if targetEnvironment(macCatalyst)
import Foundation

@MainActor
extension AppModel {
    func usesLocalMCP(for session: SessionInfo) -> Bool {
        guard let reader = localMCPReader, reader.status != nil,
              let projectId = session.projectId,
              let snapshot = reader.meshSnapshots[projectId],
              snapshot.executions.contains(where: {
                  DesktopCatalogSources.matches(session, projectId: projectId, execution: $0)
              }) else { return false }
        let linked = Set(connectionRegistry.connections.map(\.id))
        let remote = !(Set(sessionSourceRooms[session.sessionId] ?? []).intersection(linked)).isEmpty
        return !remote || session.computerId == reader.status?.endpointId
    }

    func captureMacRemoteCatalog(_ status: SessionsStatus, fromRoom room: String) {
        guard connectionRegistry.connections.contains(where: { $0.id == room }) else { return }
        let previous = macRemoteCatalogs[room]
        let previousRows = (previous?.sessions ?? []) + (previous?.history ?? [])
        func prepare(_ rows: [SessionInfo]) -> [SessionInfo] {
            Self.filterRealCatalogSessions(Self.deduplicatedSessions(rows), allowDemo: false).map { row in
                let old = previousRows.first {
                    $0.sessionId == row.sessionId && $0.agent == row.agent
                        && $0.computerId == row.computerId && $0.projectId == row.projectId
                        && $0.taskId == row.taskId
                }
                return Self.retainingCapabilities(incoming: row, previous: old)
            }
        }
        var clean = status
        clean.sessions = prepare(status.sessions)
        clean.history = status.history.map(prepare) ?? previous?.history
        macRemoteCatalogs[room] = clean
        resumeChatQueues(observed: clean.sessions + (clean.history ?? []), fromRoom: room)
    }

    func refreshMacCombinedCatalog() {
        guard let reader = localMCPReader else { return }
        MacLocalProjection.apply(reader.meshSnapshots, to: self)
    }
}
#endif
