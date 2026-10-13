import Foundation

/// Repository identity is authoritative; similarly named forks remain separate.
enum ProjectInsightReports {
    static func reports(_ snapshot: ProjectMeshSnapshot) -> [ProjectRepositoryGraph] {
        let revisions = Set((snapshot.bindings ?? []).compactMap { binding -> String? in
            guard binding.available, let revision = binding.revision else { return nil }
            return "\(binding.repositoryId)\u{1f}\(revision)"
        })
        let candidates = (snapshot.repositoryGraphs ?? []).filter { $0.projectId == snapshot.projectId }
        return Dictionary(grouping: candidates, by: \.repositoryId).values.compactMap { rows in
            rows.enumerated().max { left, right in
                let lhs = rank(left.element, revisions: revisions)
                let rhs = rank(right.element, revisions: revisions)
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
        let reports = reports(snapshot)
        return (snapshot.bindings ?? []).filter(\.available).contains { binding in
            !reports.contains { $0.repositoryId == binding.repositoryId && isAnalyzed($0)
                && (binding.revision == nil || ($0.sourceRevision ?? $0.revision) == binding.revision) }
        }
    }

    static func hasEvidence(_ snapshot: ProjectMeshSnapshot) -> Bool {
        snapshot.backbone != nil || reports(snapshot).contains(where: isAnalyzed)
    }

    static func isAnalyzed(_ report: ProjectRepositoryGraph) -> Bool {
        report.analysisStatus == "COMPLETE" || report.analysisStatus == "INCOMPLETE"
    }

    private static func rank(_ report: ProjectRepositoryGraph, revisions: Set<String>) -> Int {
        let valid = isAnalyzed(report)
        let current = revisions.contains("\(report.repositoryId)\u{1f}\(report.sourceRevision ?? report.revision)")
        return (valid ? 8 : 0) + (current ? 4 : 0)
            + (report.analysisStatus == "COMPLETE" ? 2 : 0) + (report.codeMap != nil ? 1 : 0)
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
