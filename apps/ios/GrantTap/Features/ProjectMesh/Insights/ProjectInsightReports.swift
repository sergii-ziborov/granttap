import Foundation

/// Repository identity is authoritative; similarly named forks remain separate.
enum ProjectInsightReports {
    static func reports(_ snapshot: ProjectMeshSnapshot) -> [ProjectRepositoryGraph] {
        reports(snapshot, identities: identityMap(snapshot))
    }

    private static func reports(_ snapshot: ProjectMeshSnapshot, identities: [String: String]) -> [ProjectRepositoryGraph] {
        let identity = { identities[$0] ?? $0 }
        let revisions = Set((snapshot.bindings ?? []).compactMap { binding -> String? in
            let canonical = identity(binding.repositoryId)
            guard binding.available,
                  let revision = observedRevision(binding, canonical: canonical, snapshot: snapshot) else { return nil }
            return "\(canonical)\u{1f}\(revision)"
        })
        let candidates = (snapshot.repositoryGraphs ?? []).filter { $0.projectId == snapshot.projectId }
        return Dictionary(grouping: candidates, by: { identity($0.repositoryId) }).compactMap { canonical, rows in
            rows.enumerated().max { left, right in
                let lhs = rank(left.element, revisions: revisions, canonical: canonical)
                let rhs = rank(right.element, revisions: revisions, canonical: canonical)
                if lhs == rhs, (left.element.repositoryId == canonical) != (right.element.repositoryId == canonical) {
                    return right.element.repositoryId == canonical
                }
                return lhs == rhs ? left.offset < right.offset : lhs < rhs
            }?.element
        }.sorted {
            let lhs = isAnalyzed($0)
            let rhs = isAnalyzed($1)
            if lhs != rhs { return lhs }
            return $0.repositoryId < $1.repositoryId
        }
    }

    static func needsAnalysis(_ snapshot: ProjectMeshSnapshot) -> Bool {
        let identities = identityMap(snapshot)
        let reports = reports(snapshot, identities: identities)
        return (snapshot.bindings ?? []).filter(\.available).contains { binding in
            let canonical = identities[binding.repositoryId] ?? binding.repositoryId
            let revision = observedRevision(binding, canonical: canonical, snapshot: snapshot)
            return !reports.contains {
                (identities[$0.repositoryId] ?? $0.repositoryId) == canonical && isAnalyzed($0)
                    && (revision == nil || ($0.sourceRevision ?? $0.revision) == revision)
            }
        }
    }

    private static func identityMap(_ snapshot: ProjectMeshSnapshot) -> [String: String] {
        let ids = Set((snapshot.bindings ?? []).map(\.repositoryId)
            + (snapshot.repositoryGraphs ?? []).map(\.repositoryId))
        return Dictionary(uniqueKeysWithValues: ids.map {
            ($0, RepositoryIdentityIndex.canonical($0, snapshots: [snapshot]))
        })
    }

    static func hasEvidence(_ snapshot: ProjectMeshSnapshot) -> Bool {
        snapshot.backbone != nil || reports(snapshot).contains(where: isAnalyzed)
    }

    static func isAnalyzed(_ report: ProjectRepositoryGraph) -> Bool {
        report.analysisStatus == "COMPLETE" || report.analysisStatus == "INCOMPLETE"
    }

    private static func rank(_ report: ProjectRepositoryGraph, revisions: Set<String>, canonical: String) -> Int {
        let valid = isAnalyzed(report)
        let current = revisions.contains("\(canonical)\u{1f}\(report.sourceRevision ?? report.revision)")
        return (valid ? 8 : 0) + (current ? 4 : 0)
            + (report.analysisStatus == "COMPLETE" ? 2 : 0) + (report.codeMap != nil ? 1 : 0)
    }

    private static func observedRevision(_ binding: ProjectBindingSummary, canonical: String,
                                         snapshot: ProjectMeshSnapshot) -> String? {
        guard canonical != binding.repositoryId, binding.revision != nil else { return binding.revision }
        let latest = (snapshot.repositoryDetails ?? []).filter {
            $0.projectId == snapshot.projectId && $0.repositoryId == binding.repositoryId && $0.endpointId == binding.endpointId
        }.max { $0.observedAt < $1.observedAt }
        guard latest?.status == "ready", latest?.canonicalRepositoryId == canonical else { return binding.revision }
        return latest?.revision ?? binding.revision
    }

    static func retainingEnrichment(
        _ fresh: ProjectMeshSnapshot, from previous: ProjectMeshSnapshot?
    ) -> ProjectMeshSnapshot {
        guard let previous, previous.projectId == fresh.projectId,
              previous.bindings == fresh.bindings,
              previous.publisherEndpointId != nil else { return fresh }
        var result = fresh
        result.publisherEndpointId = fresh.publisherEndpointId ?? previous.publisherEndpointId
        result.skills = fresh.skills ?? previous.skills
        result.mcpServers = fresh.mcpServers ?? previous.mcpServers
        result.capabilityObservations = fresh.capabilityObservations ?? previous.capabilityObservations
        result.modelCatalog = fresh.modelCatalog ?? previous.modelCatalog
        result.backbone = fresh.backbone ?? previous.backbone
        result.repositoryGraphs = fresh.repositoryGraphs ?? previous.repositoryGraphs
        result.repositoryDetails = fresh.repositoryDetails ?? previous.repositoryDetails
        result.cortex = fresh.cortex ?? previous.cortex
        result.knowledge = fresh.knowledge ?? previous.knowledge
        result.supersededKnowledgeRecordIds = fresh.supersededKnowledgeRecordIds
            ?? previous.supersededKnowledgeRecordIds
        return result
    }
}
