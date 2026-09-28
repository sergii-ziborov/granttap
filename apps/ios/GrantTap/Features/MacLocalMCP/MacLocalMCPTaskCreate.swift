#if targetEnvironment(macCatalyst)
import Foundation

struct MacLocalTaskCreateResult: Decodable, Sendable {
    let operation: String
    let created: Bool
    let session_id: String?
    let error: String?
}

extension MacLocalMCPClient {
    static func createTask(
        socketPath: String, projectId: String, bindingId: String,
        endpointId: String, provider: String, text: String, model: String?,
        attachments: [AttachmentDraft] = []
    ) async throws -> MacLocalTaskCreateResult {
        let batch = attachments.isEmpty ? nil : try MacLocalAttachmentBatch(attachments)
        defer { batch?.remove() }
        var input = [
            "project_id": projectId, "binding_id": bindingId,
            "endpoint_id": endpointId, "provider": provider,
            "text": text, "operation_id": UUID().uuidString.lowercased(),
        ]
        if let model, !model.isEmpty { input["model"] = model }
        if let batch { input["attachments_json"] = batch.manifest }
        let data = try await read(socketPath: socketPath,
                                  operation: "desktop.task_create", input: input)
        let result = try JSONDecoder().decode(MacLocalTaskCreateResult.self, from: data)
        guard result.operation == "desktop.task_create",
              (result.error?.count ?? 0) <= 500 else {
            throw MacLocalMCPError.incompatible
        }
        return result
    }
}

extension MacLocalMCPModel {
    func createTask(
        projectId: String, bindingId: String, endpointId: String,
        provider: String, text: String, model: String?, attachments: [AttachmentDraft] = []
    ) async throws -> MacLocalTaskCreateResult {
        guard let status, let socket = status.desktopEngineSocket,
              status.endpointId == endpointId else { throw MacLocalMCPError.unavailable }
        return try await MacLocalMCPClient.createTask(
            socketPath: socket, projectId: projectId, bindingId: bindingId,
            endpointId: endpointId, provider: provider, text: text, model: model, attachments: attachments
        )
    }
}
#endif
