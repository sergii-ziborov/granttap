import Foundation

/// All choices remain inside the selected Mesh and its computer bindings.
struct ProjectTaskCreationContext {
    let snapshot: ProjectMeshSnapshot
    let policy: ProjectExecutionPolicy?
    let enabledProviders: Set<String>
    var localEndpointId: String? = nil
    var rooms: [String: String] = [:]

    var providers: [String] { AgentIdentity.composeIds.filter { enabledProviders.contains($0) } }
    var endpointIds: [String] {
        let ids = Set((snapshot.bindings ?? []).filter {
            $0.projectId == snapshot.projectId && $0.available
        }.map(\.endpointId))
        if policy?.mode == "pinned", let target = policy?.targetEndpointId { return [target] }
        return ids.sorted()
    }

    func bindings(on endpoint: String) -> [ProjectBindingSummary] {
        (snapshot.bindings ?? []).filter {
            $0.projectId == snapshot.projectId && $0.endpointId == endpoint
                && $0.available && $0.localPathHint?.isEmpty == false
        }.sorted {
            if ($0.repositoryId == snapshot.project.canonicalRepositoryId)
                != ($1.repositoryId == snapshot.project.canonicalRepositoryId) {
                return $0.repositoryId == snapshot.project.canonicalRepositoryId
            }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    func catalog(provider: String, endpoint: String) -> TurnModelCatalog {
        .resolve(agent: provider, endpointId: endpoint, catalogs: snapshot.modelCatalog ?? [])
    }

    func routeProblem(endpoint: String, bindingId: String) -> String? {
        if endpoint.isEmpty { return L("No computer is available in this Mesh.") }
        if policy?.mode == "pinned" {
            guard policy?.targetEndpointId == endpoint else { return L("This Mesh is pinned to another computer.") }
            switch policy?.hostGrantStatus {
            case "applied": break
            case "unavailable": return L("The pinned execution host is unavailable.")
            default: return L("The pinned execution host has not confirmed its grant.")
            }
        }
        if endpoint != localEndpointId && rooms[endpoint] == nil {
            return L("This computer is not connected to the Mesh.")
        }
        if !bindings(on: endpoint).contains(where: { $0.bindingId == bindingId }) {
            return L("Choose a workspace registered on this computer.")
        }
        return nil
    }

    static func workspaceName(_ binding: ProjectBindingSummary) -> String {
        binding.repositoryId.split(separator: "/").last.map(String.init) ?? binding.displayName
    }
}
