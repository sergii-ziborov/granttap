import Foundation

struct ProjectMeshStatistics: Equatable {
    let tasks: Int
    let activeTasks: Int
    let executions: Int
    let activeExecutions: Int
    let repositories: Int
    let graphNodes: Int
    let graphRelations: Int
    let pendingRelations: Int
    let skills: Int
    let mcpServers: Int
    let models: Int
    let cortexEndpoints: Int
    let cortexPackets: Int
    let cortexSelectedTokens: Int
    let cortexOmittedTokens: Int
    let claims: Int
    let dependencies: Int
    let events: Int

    static func presented(_ snapshot: ProjectMeshSnapshot, sessions: [SessionInfo]) -> ProjectMeshSnapshot {
        var result = snapshot
        result.tasks = ProjectMeshRecency.rows(snapshot.tasks, snapshot: snapshot, sessions: sessions).map { row in
            var task = row.task
            task.state = row.state
            return task
        }
        return result
    }

    static func make(_ snapshot: ProjectMeshSnapshot) -> ProjectMeshStatistics {
        let reports = ProjectInsightReports.reports(snapshot).filter { $0.analysisStatus != "UNAVAILABLE" }
        let graphNodes = (snapshot.backbone?.nodes.count ?? 0)
            + reports.reduce(0) { $0 + $1.totalNodes }
        let graphRelations = (snapshot.backbone?.relations.count ?? 0)
            + reports.reduce(0) { $0 + $1.totalRelations }
        let repositories = Set((snapshot.bindings ?? []).map(\.repositoryId)
            + [snapshot.project.canonicalRepositoryId]).count
        return ProjectMeshStatistics(
            tasks: snapshot.tasks.count,
            activeTasks: snapshot.tasks.filter {
                ["working", "blocked", "needs_user", "handoff"].contains($0.state)
            }.count,
            executions: snapshot.executions.count,
            activeExecutions: snapshot.executions.filter { $0.endedAt == nil }.count,
            repositories: repositories,
            graphNodes: graphNodes,
            graphRelations: graphRelations,
            pendingRelations: snapshot.backbone?.pendingCandidateCount ?? 0,
            skills: snapshot.skills?.count ?? 0,
            mcpServers: snapshot.mcpServers?.count ?? 0,
            models: snapshot.modelCatalog?.flatMap(\.models).count ?? 0,
            cortexEndpoints: snapshot.cortex?.count ?? 0,
            cortexPackets: snapshot.cortex?.filter { $0.packet != nil }.count ?? 0,
            cortexSelectedTokens: snapshot.cortex?.reduce(0) {
                $0 + ($1.packet?.selectedEstimatedTokens ?? 0)
            } ?? 0,
            cortexOmittedTokens: snapshot.cortex?.reduce(0) {
                $0 + ($1.packet?.omittedEstimatedTokens ?? 0)
            } ?? 0,
            claims: snapshot.claims.count,
            dependencies: snapshot.dependencies.count,
            events: snapshot.events.count
        )
    }
}
