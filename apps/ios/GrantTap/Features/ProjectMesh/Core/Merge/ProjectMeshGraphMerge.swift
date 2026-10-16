import Foundation

/// Repository Graphs from several reports of one Project.
///
/// Graphs are merged by repository, newest report first, so every computer's
/// working Graph stays visible. A failure is different: once a newer report
/// that carries Graphs no longer names it, the computer stopped reporting it —
/// a folder that was never a repository, a checkout that moved — and keeping
/// it would leave Mesh Health showing an error nobody can clear.
enum ProjectMeshGraphMerge {
    static func merged(current: ProjectMeshSnapshot, incoming: ProjectMeshSnapshot) -> [ProjectRepositoryGraph]? {
        let incomingIsNewer = incoming.generatedAt >= current.generatedAt
        let newer = incomingIsNewer ? incoming : current
        let older = incomingIsNewer ? current : incoming
        var byRepository: [String: ProjectRepositoryGraph] = [:]
        var order: [String] = []
        let named = newer.repositoryGraphs.map { Set($0.map(\.repositoryId)) }
        for report in (older.repositoryGraphs ?? []) + (newer.repositoryGraphs ?? []) {
            if byRepository[report.repositoryId] == nil { order.append(report.repositoryId) }
            byRepository[report.repositoryId] = report
        }
        let graphs = order.compactMap { id -> ProjectRepositoryGraph? in
            guard let report = byRepository[id] else { return nil }
            if report.analysisStatus == "UNAVAILABLE", let named, !named.contains(id) { return nil }
            return report
        }
        return graphs.isEmpty ? nil : graphs
    }
}
