#if targetEnvironment(macCatalyst)
import Foundation

private struct MacLocalTaskQueueResult: Decodable {
    let operation: String
    let accepted: Bool
    let job: RelayTaskJobReceipt?
    let error: String?
}

extension MacLocalMCPModel {
    func queuedTask(_ row: OutgoingDelivery, action: String) async throws -> RelayTaskJobReceipt {
        guard status?.taskQueueAvailable == true else {
            throw NSError(domain: "GrantTap.Queue", code: 1, userInfo: [NSLocalizedDescriptionKey:
                L("Update MCP on this computer to use relay queues.")])
        }
        guard let sessionId = row.sessionId, let projectId = row.projectId,
              let taskId = row.chatQueue?.taskId else { throw MacLocalMCPError.incompatible }
        return try await Task.detached(priority: .utility) {
            var input: [String: Any] = ["project_id": projectId, "task_id": taskId,
                "session_id": sessionId, "delivery_id": row.id, "action": action]
            var batch: MacLocalAttachmentBatch?
            defer { batch?.remove() }
            if action == "put" {
                let attachments = try row.attachments.map { attachment -> AttachmentDraft in
                    guard let data = Data(base64Encoded: attachment.data) else { throw MacLocalMCPError.incompatible }
                    return AttachmentDraft(name: attachment.name, mimeType: attachment.mimeType, data: data)
                }
                if !attachments.isEmpty { batch = try MacLocalAttachmentBatch(attachments) }
                input["text"] = row.text
                input["created_at"] = floor(row.chatQueue?.queuedAt ?? row.createdAt)
                input["not_before"] = floor(row.chatQueue?.notBefore ?? row.createdAt)
                if row.chatQueue?.sendImmediately == true { input["delivery_mode"] = "immediate" }
                if let batch { input["attachments_json"] = batch.manifest }
                if let value = row.model { input["model"] = value }
                if let value = row.effort { input["effort"] = value }
                if let value = row.preferredMcp { input["preferred_mcp"] = value }
                if let value = row.skill { input["skill"] = value }
                if let value = row.permissionMode { input["permission_mode"] = value }
            }
            let data = try await MacNativeTransport.invoke(operation: "desktop.task_queue", input: input)
            let result = try JSONDecoder().decode(MacLocalTaskQueueResult.self, from: data)
            guard result.operation == "desktop.task_queue", (result.error?.count ?? 0) <= 500 else {
                throw MacLocalMCPError.incompatible
            }
            guard result.accepted, let job = result.job, job.id == row.id else {
                throw NSError(domain: "GrantTap.Queue", code: 2, userInfo: [NSLocalizedDescriptionKey:
                    L(result.error ?? "The relay has not confirmed this change. The task remains in the queue.")])
            }
            return job
        }.value
    }
}
#endif
