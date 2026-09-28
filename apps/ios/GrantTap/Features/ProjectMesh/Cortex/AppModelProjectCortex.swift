import Foundation

@MainActor
extension AppModel {
    func setProjectCortex(
        projectId: String,
        endpointId: String,
        configuration: CortexIntegrationSet,
        completion: @escaping (Bool) -> Void
    ) {
        guard meshSnapshots[projectId] != nil,
              let room = cortexRoom(projectId: projectId, endpointId: endpointId),
              let relay = relaysByRoom[room],
              configuration.projectId == projectId,
              (512...262_144).contains(configuration.maxTokens)
        else { completion(false); return }
        relay.sendProjectCortex(configuration) { error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }

    private func cortexRoom(projectId: String, endpointId: String) -> String? {
        if let mapped = meshComputerRoomByEndpointId[endpointId],
           meshProjectSourceRooms[projectId]?.contains(mapped) == true { return mapped }
        let rooms = meshProjectSourceRooms[projectId] ?? []
        return rooms.count == 1 ? rooms.first : nil
    }
}
