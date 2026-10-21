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

/// Build the repository index once, so a scrolling row never re-selects every report.
struct ProjectHealthPresentation: Equatable {
    struct Repository: Identifiable, Equatable {
        let id: String
        let name: String
        let disambiguation: String?
        let report: ProjectRepositoryGraph?
        let stale: Bool

        var ready: Bool { report?.analysisStatus == "COMPLETE" && report?.truncated == false && !stale }
        var usable: Bool { report.map(ProjectInsightReports.isAnalyzed) ?? false }
        var failed: Bool { report?.analysisStatus == "UNAVAILABLE" }
        var current: Bool { usable && !stale }

        var statusTitle: String {
            guard let report else { return L("No report") }
            if report.analysisStatus == "UNAVAILABLE" { return L("Needs attention") }
            if usable && stale { return L("Saved report · needs refresh") }
            if ready { return L("Ready") }
            return L(usable ? "Current · partial report" : "Architecture needs refresh")
        }

        var detail: String? {
            guard let report else { return L("No architecture analysis reported for this repository.") }
            if report.analysisStatus == "UNAVAILABLE" {
                return ProjectRepositoryGraph.unavailableReason(report.analysisErrorCode)
            }
            guard usable else { return L("Build architecture now to receive a current report.") }
            return [LPlural(report.totalNodes, one: "%d component", many: "%d components"),
                    LPlural(report.totalRelations, one: "%d relation", many: "%d relations")].joined(separator: " · ")
        }
    }

    let repositories: [Repository]
    let reports: [ProjectRepositoryGraph]
    let computers: [ProjectHealthDiagnostics.Computer]
    let needsAnalysis: Bool
    var readyCount: Int { repositories.filter(\.ready).count }
    var attentionCount: Int { repositories.count - readyCount }
    var availableCount: Int { repositories.filter(\.usable).count }
    var currentCount: Int { repositories.filter(\.current).count }
    var savedCount: Int { repositories.filter { $0.usable && $0.stale }.count }
    var errorCount: Int { repositories.filter(\.failed).count }

    init(snapshot: ProjectMeshSnapshot, connections: [LinkedComputer]) {
        let ids = ProjectHealthDiagnostics.graphRepositoryIds(snapshot)
        reports = ProjectInsightReports.reports(snapshot)
        let stale = ProjectInsightReports.staleRepositoryIds(snapshot, reports: reports)
        let indexed = Dictionary(grouping: reports) {
            RepositoryIdentityIndex.canonical($0.repositoryId, snapshots: [snapshot])
        }
        let names = Dictionary(grouping: ids, by: ProjectRepositories.repositoryLeaf)
        repositories = ids.map { id in
            let name = ProjectRepositories.repositoryLeaf(id)
            return Repository(id: id, name: name,
                disambiguation: names[name, default: []].count > 1 ? id : nil,
                report: indexed[id]?.first, stale: stale.contains(id))
        }
        computers = ProjectHealthDiagnostics.computers(snapshot, connections: connections)
        needsAnalysis = !stale.isEmpty
    }
}

/// Unrelated AppModel changes do not rebuild Health's report and identity indices.
final class ProjectHealthPresentationCache {
    private var snapshot: ProjectMeshSnapshot?
    private var connections: [LinkedComputer] = []
    private var presentation: ProjectHealthPresentation?

    func value(for next: ProjectMeshSnapshot, connections nextConnections: [LinkedComputer]) -> ProjectHealthPresentation {
        if snapshot == next, connections == nextConnections, let presentation { return presentation }
        let result = ProjectHealthPresentation(snapshot: next, connections: nextConnections)
        snapshot = next
        connections = nextConnections
        presentation = result
        return result
    }
}
