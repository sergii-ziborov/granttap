#if targetEnvironment(macCatalyst)
import Foundation

private struct MacLocalInvocationHistory: Decodable {
    let operation: String
    let project_id: String
    let task_id: String
    let events: [ProjectInvocationRow]
    let unavailable: Bool?
}

extension MacLocalMCPModel {
    func invocationHistory(projectId: String, taskId: String) async throws
        -> (records: [ProjectInvocationRecord], unavailable: Bool) {
        guard let socket = status?.desktopEngineSocket else {
            throw MacLocalMCPError.unavailable
        }
        let data = try await MacLocalMCPClient.read(
            socketPath: socket, operation: "desktop.invocation_history",
            input: ["project_id": projectId, "task_id": taskId]
        )
        let page = try JSONDecoder().decode(MacLocalInvocationHistory.self, from: data)
        guard page.operation == "desktop.invocation_history",
              page.project_id == projectId, page.task_id == taskId,
              page.events.count <= 16,
              page.events.allSatisfy({ $0.event.project_id == projectId
                  && $0.event.task_id == taskId && $0.event.isWellFormed }) else {
            throw MacLocalMCPError.incompatible
        }
        return (page.events.map {
            ProjectInvocationRecord(room: "local-mac", sequence: $0.sequence, event: $0.event)
        }, page.unavailable == true)
    }
}
#endif
