import Foundation

struct ChatMessageQueueContext: Codable, Equatable {
    enum Transport: String, Codable { case relay, localMCP }
    var waiting: Bool
    let transport: Transport
    let taskId: String?
    var queuedAt: Double? = nil
}

enum ChatMessageQueuePolicy {
    static func canCancel(_ delivery: OutgoingDelivery) -> Bool {
        delivery.chatQueue != nil && delivery.admissionRejected != true
            && ((delivery.state == .queued && delivery.attempts == 0
                && delivery.processingAcknowledgedAt == nil)
                || delivery.state == .failed)
    }

    static func sameChat(_ first: OutgoingDelivery, _ second: OutgoingDelivery) -> Bool {
        first.sessionId == second.sessionId && first.roomId == second.roomId
            && first.agent == second.agent && first.projectId == second.projectId
            && first.chatQueue?.taskId == second.chatQueue?.taskId
            && first.chatQueue?.transport == second.chatQueue?.transport
    }

    /// A stale catalog cannot bypass an older in-flight or failed follow-up.
    static func ready(_ deliveries: [OutgoingDelivery], observed: [SessionInfo]) -> [String] {
        let ordered = TaskDeliveryQueue.oldestFirst(deliveries)
        return ordered.compactMap { row in
            guard row.chatQueue?.waiting == true, row.state == .queued,
                  row.admissionRejected != true,
                  let session = observed.first(where: {
                      $0.sessionId == row.sessionId && AgentIdentity.normalize($0.agent) == row.agent
                          && (row.projectId == nil || $0.projectId == row.projectId)
                          && (row.chatQueue?.taskId == nil || $0.taskId == row.chatQueue?.taskId)
                  }), !session.isPaused, ["idle", "finished"].contains(session.state),
                  !ordered.contains(where: {
                      $0.chatQueue == nil && $0.sessionId == row.sessionId && $0.roomId == row.roomId
                          && $0.agent == row.agent && ($0.state == .sending || $0.state == .queued)
                          && ($0.attempts > 0 || $0.processingAcknowledgedAt != nil)
                  }),
                  !ordered.contains(where: {
                      $0.id != row.id && $0.chatQueue != nil && $0.state != .delivered
                          && sameChat($0, row)
                          && ($0.chatQueue?.waiting == false || $0.state == .failed
                              || $0.createdAt < row.createdAt
                              || ($0.createdAt == row.createdAt && $0.id < row.id))
                  }) else { return nil }
            return row.id
        }
    }
}
