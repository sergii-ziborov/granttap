import Foundation

@MainActor
extension AppModel {
    func forwardMesh<T: Codable>(
        _ payload: T, scopeId: String, purpose: String,
        sourceRoom: String, targetRoom: String
    ) {
        if let link = memberLinks.first(where: { $0.id == targetRoom }) {
            guard link.joinedAt != nil else { return }
            switch purpose {
            case "project": guard memberCanAccessProject(link, projectId: scopeId) else { return }
            case "task":
                guard let event = payload as? ProjectMeshEvent,
                      memberCanAccessProject(link, projectId: event.projectId) else { return }
            case "session":
                guard let projectId = projectId(ofSession: scopeId),
                      memberCanAccessProject(link, projectId: projectId) else { return }
            default: return
            }
        }
        guard agentMeshPreferences.meshEnabled,
              sourceRoom != targetRoom,
              isAuthorizedMeshRoom(targetRoom),
              let source = meshRelay(forRoom: sourceRoom),
              let target = meshRelay(forRoom: targetRoom),
              let key = source.sessionKey(for: scopeId)
        else { return }
        target.forwardMesh(payload, scopeId: scopeId, key: key, purpose: purpose) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in self?.append("mesh forward failed: \(error.localizedDescription)") }
        }
    }

    func meshRelay(forRoom room: String) -> RelayClient? {
        relaysByRoom[room] ?? meshEndpointRoomToId[room].flatMap { meshEndpointRelaysById[$0] }
    }

    private func isAuthorizedMeshRoom(_ room: String) -> Bool {
        connectionRegistry.connections.contains(where: { $0.id == room })
            || meshEndpointRoomToId[room] != nil
    }

}
