import Foundation

/// Rebuilt once when Mesh changes, shared by every reader of a Task timeline.
final class TaskMeshEventIndex {
    private var revision: UInt64?
    private var byTask: [String: [ProjectMeshEvent]] = [:]

    func events(for taskId: String, revision: UInt64,
                snapshots: [String: ProjectMeshSnapshot]) -> [ProjectMeshEvent] {
        if self.revision != revision {
            byTask = Dictionary(grouping: snapshots.values.flatMap(\.events), by: \.taskId)
                .mapValues { $0.sorted { $0.createdAt < $1.createdAt } }
            self.revision = revision
        }
        return byTask[taskId] ?? []
    }
}
