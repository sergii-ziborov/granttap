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
        snapshot.repositoryGraphs?.first { $0.repositoryId == repositoryId }
    }
}
