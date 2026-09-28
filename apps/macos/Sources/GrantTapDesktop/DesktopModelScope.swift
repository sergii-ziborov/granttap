import DesktopInspectorCore
import Foundation

extension DesktopModel {
    func currentScope(for current: InspectorSnapshot) -> String?? {
        let project = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = socketPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let scopedTask = task.isEmpty ? nil : task
        guard project == current.project?.project_id, scopedTask == current.taskId,
              path == current.sourceSocketPath else {
            message = "Refresh after changing Engine, Project or Task."
            return nil
        }
        return .some(scopedTask)
    }
}
