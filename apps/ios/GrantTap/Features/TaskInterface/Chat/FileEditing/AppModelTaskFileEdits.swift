import Foundation

@MainActor
extension AppModel {
    /// Admission keeps the complete proposed file in the existing durable, encrypted Task queue.
    func queueTaskFileEdit(snapshot: TaskWorkspaceSnapshot, replacement: String,
                          to session: SessionInfo) throws -> String? {
        guard snapshot.sessionId == session.sessionId else { throw TaskFileEditRequest.Failure.incomplete }
        let request = try TaskFileEditRequest(snapshot: snapshot, replacement: replacement)
        let previous = Set(deliveries.map(\.id))
        guard queueChatMessage(request.message, to: session, attachments: [try request.attachment()],
            overrides: turnOverrides.resolved(sessionId: session.sessionId, agent: session.agent)) else { return nil }
        return deliveries.first { !previous.contains($0.id) }?.id
    }
}
