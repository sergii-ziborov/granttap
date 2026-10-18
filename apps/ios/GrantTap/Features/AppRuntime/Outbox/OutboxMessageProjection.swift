import Foundation

extension AppModel {
    /// Exact user.message fields consumed by the relay send. Keeping this as a
    /// single projection makes retries preserve provider identity and prevents
    /// a shared native UUID from selecting the wrong provider on the Mac.
    func wireUserMessage(for delivery: OutgoingDelivery) -> UserMessage {
        let correlatedReply = delivery.requestId?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty == false
        let localOnly = delivery.sessionId.map { localOnlySessionIds.contains($0) } ?? false
        let session = delivery.sessionId.flatMap {
            knownSession(for: $0, preferredAgent: delivery.agent)
        }
        let wireSessionId: String? = {
            if correlatedReply { return delivery.sessionId }
            return localOnly ? nil : delivery.sessionId
        }()
        let wireAgent: String? = {
            guard !correlatedReply else { return nil }
            let value = delivery.agent ?? session?.agent
            guard let value else { return nil }
            return AgentIdentity.normalize(value)
        }()
        let wireCwd: String? = {
            if let cwd = delivery.cwd { return cwd }
            return localOnly ? session?.cwd : nil
        }()
        return Payloads.message(
            delivery.text,
            messageId: delivery.id,
            agent: wireAgent,
            cwd: wireCwd,
            sessionId: wireSessionId,
            requestId: delivery.requestId,
            attachments: delivery.attachmentRefs == nil ? delivery.attachments : [],
            attachmentRefs: delivery.attachmentRefs ?? [],
            preferredMcp: delivery.preferredMcp,
            skill: delivery.skill,
            projectId: delivery.projectId,
            model: delivery.model,
            permissionMode: delivery.permissionMode,
            effort: delivery.effort
        )
    }
}
