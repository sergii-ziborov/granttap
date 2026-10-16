#if targetEnvironment(macCatalyst)
import Foundation

struct MacLocalTaskSendResult: Decodable, Sendable {
    let operation: String
    let accepted: Bool
    let error: String?
}

extension MacLocalMCPClient {
    @MainActor
    static func send(socketPath: String, projectId: String, taskId: String,
                     sessionId: String, text: String, deliveryId: UUID,
                     attachments: [AttachmentDraft] = [], model: String? = nil, effort: String? = nil,
                     preferredMcp: String? = nil, skill: String? = nil, permissionMode: String? = nil,
                     invoke: MacLocalTaskCommands.Invoke = { try await MacNativeTransport.invoke(operation: $0, input: $1) }) async throws
        -> MacLocalTaskSendResult {
        let batch = attachments.isEmpty ? nil : try MacLocalAttachmentBatch(attachments)
        defer { batch?.remove() }
        var input = [
            "project_id": projectId, "task_id": taskId, "session_id": sessionId,
            "text": text, "delivery_id": deliveryId.uuidString.lowercased(),
        ]
        if let batch { input["attachments_json"] = batch.manifest }
        if let model {
            guard TurnModel(rawValue: model) != nil else { throw MacLocalMCPError.incompatible }
            input["model"] = model
        }
        if let effort { input["effort"] = effort }
        if let preferredMcp { input["preferred_mcp"] = preferredMcp }
        if let skill { input["skill"] = skill }
        if let permissionMode { input["permission_mode"] = permissionMode }
        let data = try await invoke("desktop.task_send", input)
        let result = try JSONDecoder().decode(MacLocalTaskSendResult.self, from: data)
        guard result.operation == "desktop.task_send", (result.error?.count ?? 0) <= 500 else {
            throw MacLocalMCPError.incompatible
        }
        return result
    }
}

extension MacLocalMCPModel {
    func send(_ text: String, to session: SessionInfo,
              attachments: [AttachmentDraft] = [],
              deliveryId: UUID = UUID(), model: String? = nil, effort: String? = nil,
              preferredMcp: String? = nil, skill: String? = nil, permissionMode: String? = nil) async throws -> MacLocalTaskSendResult {
        guard let socket = status?.desktopEngineSocket,
              let projectId = session.projectId, let taskId = session.taskId else {
            throw MacLocalMCPError.unavailable
        }
        return try await MacLocalMCPClient.send(
            socketPath: socket, projectId: projectId, taskId: taskId,
            sessionId: session.sessionId, text: text, deliveryId: deliveryId, attachments: attachments,
            model: model, effort: effort, preferredMcp: preferredMcp, skill: skill, permissionMode: permissionMode
        )
    }
}
#endif
