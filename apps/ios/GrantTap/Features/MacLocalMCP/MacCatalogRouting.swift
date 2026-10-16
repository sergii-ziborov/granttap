#if targetEnvironment(macCatalyst)
import Foundation

@MainActor
extension AppModel {
    func usesLocalTaskDelivery(for session: SessionInfo) -> Bool {
        guard let endpoint = localMCPReader?.status?.endpointId, session.computerId == endpoint else { return false }
        return usesLocalMCP(for: session)
    }

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

    func refreshMacCombinedCatalog() {
        guard let reader = localMCPReader else { return }
        MacLocalProjection.apply(reader.meshSnapshots, to: self)
    }
}
#endif
