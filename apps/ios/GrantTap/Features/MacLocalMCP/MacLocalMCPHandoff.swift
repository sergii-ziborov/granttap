#if targetEnvironment(macCatalyst)
import Foundation

struct MacLocalTaskHandoffResult: Decodable, Sendable {
    let operation: String
    let accepted: Bool
    let error: String?
}

extension MacLocalMCPModel {
    func handoff(_ session: SessionInfo, provider: String, computer: String,
                 targetModel: String?, comment: String?, checkpoint: Bool, push: Bool) async throws
        -> MacLocalTaskHandoffResult {
        guard status?.desktopEngineSocket != nil,
              let projectId = session.projectId, let taskId = session.taskId,
              targetModel.map({ TurnModel(rawValue: $0) != nil }) ?? true else {
            throw MacLocalMCPError.unavailable
        }
        var input: [String: Any] = [
            "project_id": projectId, "task_id": taskId, "session_id": session.sessionId,
            "target_provider": provider, "target_computer": computer,
            "checkpoint": checkpoint, "push": push,
        ]
        if let targetModel { input["target_model"] = targetModel }
        if let comment, !comment.isEmpty { input["user_comment"] = comment }
        let data = try await MacNativeTransport.invoke(operation: "desktop.task_handoff", input: input)
        let result = try JSONDecoder().decode(MacLocalTaskHandoffResult.self, from: data)
        guard result.operation == "desktop.task_handoff", (result.error?.count ?? 0) <= 500 else {
            throw MacLocalMCPError.incompatible
        }
        return result
    }
}
#endif
