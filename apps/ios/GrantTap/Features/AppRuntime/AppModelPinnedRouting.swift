import Foundation

extension AppModel {
    func advertisedModels(for agent: String, sessionId: String? = nil, computerId: String? = nil) -> [String] {
        let provider = AgentIdentity.normalize(agent)
        let endpoint = computerId
            ?? sessionId.flatMap { sid in sessions.first(where: { $0.sessionId == sid })?.computerId }
        for snapshot in meshSnapshots.values {
            let catalogs = snapshot.modelCatalog ?? []
            let catalog = endpoint.flatMap { id in catalogs.first(where: { $0.endpointId == id }) }
                ?? catalogs.first
            if let catalog {
                return catalog.models.filter { $0.provider == provider }.map(\.modelId)
            }
        }
        return []
    }

    func pinnedEndpointId(forWorkspace workspace: String) -> String? {
        let path = workspace.trimmingCharacters(in: .whitespacesAndNewlines)
        for snapshot in meshSnapshots.values {
            guard snapshot.execution?.mode == .pinned,
                  let host = snapshot.execution?.targetEndpointId else { continue }
            if path.isEmpty { return host }
            if let root = snapshot.project.repositoryRoot, path.hasPrefix(root) { return host }
            if snapshot.executions.contains(where: { $0.workspace == path }) { return host }
        }
        return nil
    }

}
