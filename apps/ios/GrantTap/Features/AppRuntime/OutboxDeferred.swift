import Foundation
import SwiftUI
import UIKit

extension AppModel {
    func retryQueuedDeliveries(forRoom roomId: String? = nil) {
        pruneStaleDeliveries()
        let now = Date().timeIntervalSince1970 * 1000
        for delivery in TaskDeliveryQueue.oldestFirst(deliveries)
        where (delivery.state == .queued || delivery.state == .sending)
            && delivery.admissionRejected != true
            && delivery.awaitingSessionRemap != true
            && (roomId == nil || delivery.roomId == roomId) {
            if let acknowledgedAt = delivery.processingAcknowledgedAt {
                if let deadline = DeliveryOutboxPolicy.terminalDeadline(for: delivery) {
                    scheduleProcessingExpiry(delivery.id, at: deadline)
                }
                if delivery.processingRetryStartedAt != nil {
                    if delivery.state == .sending,
                       let generation = delivery.attemptGeneration,
                       !liveDeliveryAttemptGenerations.contains(generation) {
                        reconcileInterruptedRecoveryAttempt(delivery.id)
                        continue
                    }
                    // Recover the tiny persisted gap between reserving the one
                    // retry and entering attemptDelivery after an app restart.
                    if delivery.state == .queued,
                       delivery.attempts < maxDeliveryAttempts {
                        let retryAt = delivery.nextRetryAt ?? now
                        if retryAt <= now {
                            if delivery.roomId.map(deliveryRoomIsUp) == true {
                                attemptDelivery(delivery.id)
                            }
                        } else if let deadline = DeliveryOutboxPolicy.terminalDeadline(
                            for: delivery
                        ) {
                            scheduleRecoveryTransportRetry(
                                delivery.id,
                                attempt: delivery.attempts,
                                at: retryAt,
                                before: deadline
                            )
                        }
                    }
                    continue
                }
                let retryAt = delivery.nextRetryAt
                    ?? acknowledgedAt + DeliveryOutboxPolicy.processingRetryDelayMs
                if retryAt <= now {
                    beginProcessingRetry(delivery.id)
                } else {
                    scheduleProcessingRetry(delivery.id, at: retryAt)
                }
                continue
            }
            if now - deferredLifecycleAnchor(for: delivery)
                    < DeliveryOutboxPolicy.unacknowledgedRetentionMs,
               delivery.roomId.map(deliveryRoomIsUp) == true {
                attemptDelivery(delivery.id)
            }
        }
    }

    /// Release follow-ups only after their phone stub has been durably rewritten
    /// to the provider-native session id. The ids arrive oldest-first so several
    /// messages composed during startup retain the user's send order.
    func resumeDeferredFollowUps(_ ids: [String]) {
        for id in ids {
            guard let delivery = deliveries.first(where: { $0.id == id }),
                  delivery.state == .queued,
                  delivery.awaitingSessionRemap != true,
                  let roomId = delivery.roomId,
                  deliveryRoomIsUp(roomId),
                  relaysByRoom[roomId] != nil else { continue }
            attemptDelivery(id)
        }
    }

    /// A held follow-up has no valid wire target when its originating new task
    /// ends without a native session. Keep it visible and let an explicit retry
    /// promote that exact persisted row to a fresh new-task origin.
    func failDeferredFollowUps(forLocalSessionId sessionId: String) {
        let now = Date().timeIntervalSince1970 * 1000
        let message = L(
            "The original task ended before a native session was created. Retry this message to start a new task."
        )
        var changed = false
        for index in deliveries.indices
        where deliveries[index].sessionId == sessionId
            && deliveries[index].awaitingSessionRemap == true
            && (deliveries[index].state == .queued || deliveries[index].state == .sending) {
            if let generation = deliveries[index].attemptGeneration {
                liveDeliveryAttemptGenerations.remove(generation)
            }
            deliveries[index].state = .failed
            deliveries[index].error = message
            deliveries[index].updatedAt = now
            deliveries[index].nextRetryAt = nil
            deliveries[index].processingAcknowledgedAt = nil
            deliveries[index].processingRetryStartedAt = nil
            deliveries[index].attemptGeneration = nil
            changed = true
        }
        guard changed else { return }
        persistDeliveries()
        AuditStore.shared.record(
            "delivery", detail: "Deferred follow-up lost its session origin", outcome: "failed"
        )
    }

    func localOriginSessionId(for delivery: OutgoingDelivery) -> String? {
        guard delivery.awaitingSessionRemap != true,
              let sessionId = delivery.sessionId,
              localOnlySessionIds.contains(sessionId) else { return nil }
        return sessionId
    }

    func deferredLifecycleAnchor(for delivery: OutgoingDelivery) -> Double {
        // `false` is intentionally distinct from a legacy/nil value: it marks a
        // held row that was just released by native remap (or explicitly retried).
        return delivery.awaitingSessionRemap == false
            ? delivery.updatedAt : delivery.createdAt
    }

    /// A dropped/replaced WebSocket may never deliver its pending completion.
    /// Keep the persisted generation on the row as interruption evidence, but
    /// remove its in-process ownership so reconnect can safely resend the same
    /// message id through the bridge's durable dedupe ledger.
    func markDeliveryAttemptsInterrupted(forRoom roomId: String) {
        for delivery in deliveries where delivery.roomId == roomId {
            if let generation = delivery.attemptGeneration {
                liveDeliveryAttemptGenerations.remove(generation)
            }
        }
    }

    func scheduleProcessingRetry(_ id: String, at retryAt: Double) {
        let delay = max(0, (retryAt - Date().timeIntervalSince1970 * 1000) / 1000)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  let current = self.deliveries.first(where: { $0.id == id }),
                  current.processingAcknowledgedAt != nil,
                  current.processingRetryStartedAt == nil,
                  current.nextRetryAt == retryAt else { return }
            self.beginProcessingRetry(id)
        }
    }

    func beginProcessingRetry(_ id: String) {
        guard let index = deliveries.firstIndex(where: { $0.id == id }),
              deliveries[index].processingAcknowledgedAt != nil,
              deliveries[index].processingRetryStartedAt == nil,
              deliveries[index].attempts == 0,
              deliveries[index].requestId?.isEmpty != false,
              let roomId = deliveries[index].roomId else { return }
        guard deliveryRoomIsUp(roomId) else { return }

        let now = Date().timeIntervalSince1970 * 1000
        deliveries[index].processingRetryStartedAt = now
        deliveries[index].nextRetryAt = nil
        deliveries[index].state = .queued
        deliveries[index].attemptGeneration = nil
        persistDeliveries()
        if let deadline = DeliveryOutboxPolicy.terminalDeadline(for: deliveries[index]) {
            scheduleProcessingExpiry(id, at: deadline)
        }
        attemptDelivery(id)
    }

    func deliveryRoomIsUp(_ roomId: String) -> Bool {
        roomRuntime[roomId]?.socketUp == true
            || (roomId == connectionRegistry.preferredId && connected)
    }

    func scheduleProcessingExpiry(_ id: String, at deadline: Double) {
        let delay = max(0, (deadline - Date().timeIntervalSince1970 * 1000) / 1000)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  let index = self.deliveries.firstIndex(where: { $0.id == id }),
                  DeliveryOutboxPolicy.terminalDeadline(for: self.deliveries[index]) == deadline,
                  Date().timeIntervalSince1970 * 1000 >= deadline else { return }
            let now = Date().timeIntervalSince1970 * 1000
            let failedOriginSessionId = self.localOriginSessionId(
                for: self.deliveries[index]
            )
            self.deliveries[index].state = .failed
            self.deliveries[index].error = L("No terminal response arrived from the computer.")
            self.deliveries[index].updatedAt = now
            self.deliveries[index].nextRetryAt = nil
            self.deliveries[index].processingAcknowledgedAt = nil
            self.deliveries[index].processingRetryStartedAt = nil
            if let generation = self.deliveries[index].attemptGeneration {
                self.liveDeliveryAttemptGenerations.remove(generation)
            }
            self.deliveries[index].attemptGeneration = nil
            self.persistDeliveries()
            if let failedOriginSessionId {
                self.failDeferredFollowUps(forLocalSessionId: failedOriginSessionId)
            }
            AuditStore.shared.record(
                "delivery", detail: "Terminal response timed out", outcome: "failed"
            )
            self.pushToWatch()
        }
    }
}
