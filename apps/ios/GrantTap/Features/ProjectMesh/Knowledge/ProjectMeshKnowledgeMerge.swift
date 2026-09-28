import Foundation

enum ProjectMeshKnowledgeMerge {
    static func merge(
        into result: inout ProjectMeshSnapshot,
        current: ProjectMeshSnapshot, incoming: ProjectMeshSnapshot
    ) {
        result.supersededKnowledgeRecordIds = correctedIds(
            current.supersededKnowledgeRecordIds, incoming.supersededKnowledgeRecordIds
        )
        result.knowledge = merge(
            current.knowledge, incoming.knowledge,
            correctedIds: Set(result.supersededKnowledgeRecordIds ?? [])
        )
    }

    static func correctedIds(_ current: [String]?, _ incoming: [String]?) -> [String]? {
        let ids = Set((current ?? []) + (incoming ?? []))
        return ids.isEmpty ? nil : Array(ids.sorted().suffix(128))
    }

    static func merge(
        _ current: [ProjectKnowledgeRecord]?, _ incoming: [ProjectKnowledgeRecord]?,
        correctedIds: Set<String>
    ) -> [ProjectKnowledgeRecord]? {
        var byIdentity = Dictionary((current ?? []).map { ($0.id, $0) },
                                    uniquingKeysWith: { first, _ in first })
        for item in incoming ?? [] where byIdentity[item.id] == nil {
            byIdentity[item.id] = item
        }
        guard !byIdentity.isEmpty else { return nil }
        let records = Array(byIdentity.values)
        let superseded = Set(records.compactMap { item -> String? in
            guard let previousId = item.supersedesRecordId,
                  let previous = byIdentity["\(item.projectId)\u{1f}\(previousId)"],
                  previous.visibility == item.visibility,
                  previous.category == item.category,
                  previous.repositoryId == item.repositoryId,
                  (item.visibility != "task" || previous.taskId == item.taskId)
            else { return nil }
            return previous.id
        })
        return records.filter { !superseded.contains($0.id) && !correctedIds.contains($0.recordId) }.sorted {
            $0.recordedAt == $1.recordedAt ? $0.id < $1.id : $0.recordedAt > $1.recordedAt
        }.prefix(32).map { $0 }
    }
}
