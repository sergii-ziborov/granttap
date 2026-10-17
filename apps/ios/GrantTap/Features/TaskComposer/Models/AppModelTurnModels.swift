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
        if endpoint == nil, let room = roomId ?? session.flatMap({ sourceRoom(forSessionId: $0.sessionId) })
            ?? connectionRegistry.preferredId {
            endpoint = catalogEndpoint(forRoom: room)
        }
        return turnModelCatalog(agent: agent, endpointId: endpoint)
    }

    /// The models one computer reported for one provider; nothing for an unknown computer.
    func turnModelCatalog(agent: String, endpointId: String?) -> TurnModelCatalog {
        TurnModelCatalog.resolve(agent: agent, endpointId: endpointId,
            catalogs: meshSnapshots.values.flatMap { $0.modelCatalog ?? [] })
    }

    /// The computer a room reaches, by one rule for its model list and for a
    /// transfer to it: the computer's own status report first, then the Project
    /// snapshots it published, then the chats it carries. A relaunch or an old
    /// name left in the snapshot map no longer hides its models.
    func catalogEndpoint(forRoom room: String) -> String? {
        #if targetEnvironment(macCatalyst)
        if room == "local-mcp" { return localMCPReader?.status?.endpointId }
        #endif
        if let reported = agentIntegrationsByRoom[room]?.lazy.compactMap(\.endpointId).first(where: { !$0.isEmpty }) {
            return reported
        }
        let published = meshComputerRoomByEndpointId.filter { $0.value == room }.map(\.key).sorted()
        if published.count > 1 {
            let catalogs = meshSnapshots.values.flatMap { $0.modelCatalog ?? [] }
            let freshness = { (endpoint: String) in
                catalogs.filter { $0.endpointId == endpoint }.map(\.observedAt).max() ?? -1
            }
            return published.max { freshness($0) < freshness($1) }
        }
        if let only = published.first { return only }
        let chats = Set((sessions + sessionHistory).filter { sourceRoom(forSessionId: $0.sessionId) == room }
            .compactMap(\.computerId))
        return chats.count == 1 ? chats.first : nil
    }

    /// A transfer's chosen model and effort travel with its first message, so a
    /// global default for that agent cannot silently replace them.
    func rememberTransferChoice(destination: String, model choice: String, effort: String) {
        let model = TurnModel(rawValue: choice)
        let effort = TurnEffort(rawValue: effort)
        guard model != nil || effort != nil else { return }
        var overrides = turnOverrides.chatOverrides(destination)
        if let model { overrides.model = model }
        if let effort { overrides.effort = effort }
        objectWillChange.send()
        turnOverrides.setChatOverrides(overrides, for: destination)
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
