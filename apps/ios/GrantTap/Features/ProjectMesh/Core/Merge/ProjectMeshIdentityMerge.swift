import Foundation

extension ProjectMeshLogic {
    /// Retire only an empty legacy identity from the same authenticated room
    /// and exact checkout. Anything carrying work or authority remains visible
    /// until a durable migration can preserve it.
    static func staleIdentities(
        in snapshots: [String: ProjectMeshSnapshot],
        besides incoming: ProjectMeshSnapshot,
        sourceRooms: [String: Set<String>] = [:],
        incomingRoom: String? = nil
    ) -> [String] {
        snapshots.compactMap { projectId, other in
            guard projectId != incoming.projectId,
                  other.generatedAt < incoming.generatedAt,
                  other.tasks.isEmpty, other.executions.isEmpty,
                  other.claims.isEmpty, other.events.isEmpty,
                  let incomingRoom,
                  sourceRooms[projectId]?.contains(incomingRoom) == true,
                  other.project.name.caseInsensitiveCompare(incoming.project.name) == .orderedSame,
                  rootsMatch(other.project.repositoryRoot, incoming.project.repositoryRoot)
            else { return nil }
            return projectId
        }
    }

    private static func rootsMatch(_ left: String?, _ right: String?) -> Bool {
        let left = normalizedRoot(left)
        let right = normalizedRoot(right)
        return !left.isEmpty && left == right
    }

    private static func normalizedRoot(_ value: String?) -> String {
        (value ?? "").lowercased()
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
