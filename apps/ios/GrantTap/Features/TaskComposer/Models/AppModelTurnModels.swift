import Foundation

extension AppModel {
    func turnModelCatalog(agent: String, session: SessionInfo? = nil, roomId: String? = nil) -> TurnModelCatalog {
        var endpoint = session?.computerId
        #if targetEnvironment(macCatalyst)
        if let session, usesLocalTaskDelivery(for: session) {
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

    func turnWireOverrides(_ overrides: TurnOverrides, agent: String, session: SessionInfo?,
                           roomId: String?, modelId: String? = nil)
        -> (model: String?, permissionMode: String?, effort: String?) {
        var selection = overrides
        selection.model = modelId.flatMap(TurnModel.init(rawValue:)) ?? overrides.model
        return selection.wire(for: agent, catalog: turnModelCatalog(agent: agent, session: session, roomId: roomId),
                              currentModel: session?.model)
    }

    func refreshProviderMetadata() async {
        guard !demoMode else { return }
        #if targetEnvironment(macCatalyst)
        if let reader = localMCPReader {
            await reader.refresh()
            refreshMacCombinedCatalog()
        }
        #endif
        for room in accountVisibleRooms() { relaysByRoom[room]?.requestSessionsRefresh() }
    }

}
