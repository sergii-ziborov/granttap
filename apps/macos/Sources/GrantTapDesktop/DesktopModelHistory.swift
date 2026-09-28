import DesktopInspectorCore
import Foundation

extension DesktopModel {
    func loadOlderKnowledge() {
        guard !loading, var current = snapshot, let project = current.project?.project_id,
              let scope = currentScope(for: current),
              var page = current.knowledge, page.incomplete,
              let before = page.next_before_version else { return }
        loading = true
        Task {
            do {
                let path = current.sourceSocketPath
                let older = try await Task.detached(priority: .userInitiated) {
                    try InspectorService(client: EngineClient(socketPath: path))
                        .knowledgePage(projectId: project, taskId: scope,
                                       beforeVersion: before)
                }.value
                page.entries.append(contentsOf: older.entries)
                page.next_before_version = older.next_before_version
                page.incomplete = older.incomplete
                current.knowledge = page
                snapshot = current
                message = "Older Knowledge loaded."
            } catch {
                message = "Older Knowledge could not be loaded."
            }
            loading = false
        }
    }

    func loadOlderInvocations() {
        guard !loading, var current = snapshot, let project = current.project?.project_id,
              let scope = currentScope(for: current),
              var page = current.invocations, page.has_older else { return }
        let before = page.previous_sequence
        loading = true
        Task {
            do {
                let path = current.sourceSocketPath
                let older = try await Task.detached(priority: .userInitiated) {
                    try InspectorService(client: EngineClient(socketPath: path))
                        .invocationPage(projectId: project, taskId: scope,
                                        beforeSequence: before)
                }.value
                page.events = older.events + page.events
                page.previous_sequence = older.previous_sequence
                page.has_older = older.has_older
                current.invocations = page
                snapshot = current
                message = "Older activity loaded."
            } catch {
                message = "Older activity could not be loaded."
            }
            loading = false
        }
    }
}
