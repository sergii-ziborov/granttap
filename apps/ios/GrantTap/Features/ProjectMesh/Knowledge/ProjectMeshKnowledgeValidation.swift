import Foundation

enum ProjectMeshKnowledgeValidation {
    static func valid(
        _ records: [ProjectKnowledgeRecord]?, correctedIds: [String]?, projectId: String
    ) -> Bool {
        guard (correctedIds?.count ?? 0) <= 128,
              Set(correctedIds ?? []).count == (correctedIds?.count ?? 0),
              correctedIds?.allSatisfy({ !$0.isEmpty && $0.count <= 128 }) != false
        else { return false }
        guard let records else { return true }
        let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return records.count <= 32 && Set(records.map(\.id)).count == records.count
            && records.allSatisfy { item in
                item.projectId == projectId && !item.taskId.isEmpty && item.taskId.count <= 128
                    && !item.recordId.isEmpty && item.recordId.count <= 128
                    && ["decision", "attempt", "result"].contains(item.category)
                    && !item.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && item.content.utf8.count <= 4_096
                    && ["agent_report", "task_capsule", "observed_invocation",
                        "user_decision"].contains(item.source)
                    && item.visibility == "project"
                    && !item.sourceRef.isEmpty && item.sourceRef.count <= 256
                    && (item.repositoryId.map { !$0.isEmpty && $0.count <= 512 } ?? true)
                    && (item.commitSha.map { (7...64).contains($0.count)
                        && $0.unicodeScalars.allSatisfy(hex.contains) } ?? true)
                    && item.recordedAt.isFinite && item.recordedAt >= 0
                    && item.streamVersion >= 0
            }
    }
}
