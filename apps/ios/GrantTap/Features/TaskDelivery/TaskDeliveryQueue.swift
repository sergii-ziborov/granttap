import Foundation

enum TaskDeliveryQueue {
    static let offlineRetentionMilliseconds: Double = 24 * 60 * 60 * 1_000

    static func oldestFirst(_ deliveries: [OutgoingDelivery]) -> [OutgoingDelivery] {
        deliveries.sorted {
            let first = $0.chatQueue?.queuedAt ?? $0.createdAt
            let second = $1.chatQueue?.queuedAt ?? $1.createdAt
            if first == second { return $0.id < $1.id }
            return first < second
        }
    }

    static func retentionMilliseconds(for delivery: OutgoingDelivery) -> Double {
        if delivery.state == .queued, delivery.attempts == 0,
           delivery.processingAcknowledgedAt == nil {
            return offlineRetentionMilliseconds
        }
        return DeliveryOutboxPolicy.unacknowledgedRetentionMs
    }
}
