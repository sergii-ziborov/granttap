import Foundation

enum ProjectHealthDiagnostics {
    struct Computer: Identifiable, Equatable {
        let id: String
        let name: String
        let bindingCount: Int
        let available: Bool?
        let cortex: ProjectCortexIntegration?
    }

    static func computerName(_ endpointId: String, connections: [LinkedComputer]) -> String {
        let alias = connections.first { $0.id == endpointId }?.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = alias?.isEmpty == false ? alias! : L("Computer")
        let suffix = String(endpointId.suffix(8))
        return "\(name) · \(suffix)"
    }

    static func computers(
        _ snapshot: ProjectMeshSnapshot, connections: [LinkedComputer]
    ) -> [Computer] {
        let ids = Set(ProjectManagePresentation.endpointIds(snapshot)
            + (snapshot.cortex ?? []).map(\.endpointId))
        return ids.sorted().map { endpointId in
            let bindings = (snapshot.bindings ?? []).filter { $0.endpointId == endpointId }
            return Computer(
                id: endpointId, name: computerName(endpointId, connections: connections),
                bindingCount: bindings.count,
                available: bindings.isEmpty ? nil : bindings.contains(where: \.available),
                cortex: snapshot.cortex?.first { $0.endpointId == endpointId }
            )
        }
    }

    static func graphReport(
        for repositoryId: String, snapshot: ProjectMeshSnapshot
    ) -> ProjectRepositoryGraph? {
        let canonical = RepositoryIdentityIndex.canonical(repositoryId, snapshots: [snapshot])
        return ProjectInsightReports.reports(snapshot).first {
            RepositoryIdentityIndex.canonical($0.repositoryId, snapshots: [snapshot]) == canonical
        }
    }

    static func graphRepositoryIds(_ snapshot: ProjectMeshSnapshot) -> [String] {
        let bindings = snapshot.bindings ?? []
        let reported = Set((snapshot.repositoryGraphs ?? []).map(\.repositoryId))
        // A folder an agent ran in without Git is a workspace, not a repository
        // with a missing Graph — unless its computer still reports about it.
        let plainFolder = { (id: String) in
            id.hasPrefix("local:") && !reported.contains(id) && bindings.contains { $0.repositoryId == id }
                && bindings.allSatisfy { $0.repositoryId != id || ($0.revision ?? "").isEmpty }
        }
        let ids = ProjectMeshLogic.visibleBindings(bindings).map(\.repositoryId)
            + [snapshot.project.canonicalRepositoryId]
        return Set(ids.filter { !plainFolder($0) }
            .map { RepositoryIdentityIndex.canonical($0, snapshots: [snapshot]) }).sorted()
    }
}
