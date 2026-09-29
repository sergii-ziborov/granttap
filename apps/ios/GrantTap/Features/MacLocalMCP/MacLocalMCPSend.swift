#if targetEnvironment(macCatalyst)
import Foundation

struct MacLocalTaskSendResult: Decodable, Sendable {
    let operation: String
    let accepted: Bool
    let error: String?
}

extension MacLocalMCPClient {
    static func send(socketPath: String, projectId: String, taskId: String,
                     sessionId: String, text: String, deliveryId: UUID,
                     attachments: [AttachmentDraft] = [], model: String? = nil) async throws
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
        let data = try await read(socketPath: socketPath, operation: "desktop.task_send", input: input)
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
              deliveryId: UUID = UUID(), model: String? = nil) async throws -> MacLocalTaskSendResult {
        guard let socket = status?.desktopEngineSocket,
              let projectId = session.projectId, let taskId = session.taskId else {
            throw MacLocalMCPError.unavailable
        }
        return try await MacLocalMCPClient.send(
            socketPath: socket, projectId: projectId, taskId: taskId,
            sessionId: session.sessionId, text: text, deliveryId: deliveryId, attachments: attachments, model: model
        )
    }
}
#endif
