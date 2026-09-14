import Foundation

enum TaskDeliveryQueue {
    static let offlineRetentionMilliseconds: Double = 24 * 60 * 60 * 1_000

    static func oldestFirst(_ deliveries: [OutgoingDelivery]) -> [OutgoingDelivery] {
        deliveries.sorted {
            if $0.createdAt == $1.createdAt { return $0.id < $1.id }
            return $0.createdAt < $1.createdAt
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
