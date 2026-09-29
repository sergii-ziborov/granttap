import Foundation

extension AppModel {
    func turnModelCatalog(agent: String, session: SessionInfo? = nil, roomId: String? = nil) -> TurnModelCatalog {
        var endpoint = session?.computerId
        #if targetEnvironment(macCatalyst)
        if let session, usesLocalMCP(for: session) {
            endpoint = localMCPReader?.status?.endpointId
        } else if session == nil && roomId == nil {
            endpoint = localMCPReader?.status?.endpointId
        }
        #endif
        if endpoint == nil {
            let room = roomId ?? session.flatMap { sourceRoom(forSessionId: $0.sessionId) }
                ?? connectionRegistry.preferredId
            let candidates = meshComputerRoomByEndpointId.filter { $0.value == room }.map(\.key)
            if candidates.count == 1 { endpoint = candidates.first }
        }
        return TurnModelCatalog.resolve(agent: agent, endpointId: endpoint,
            catalogs: meshSnapshots.values.flatMap { $0.modelCatalog ?? [] })
    }
}
