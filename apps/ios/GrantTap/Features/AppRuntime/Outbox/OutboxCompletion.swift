import Foundation
import SwiftUI
import UIKit

extension AppModel {
    private func finishAcknowledgedAttempt(
        at index: Int,
        id: String,
        error: Error?,
        attempt: Int,
        delays: [TimeInterval]
    ) -> Bool {
        guard deliveries[index].processingAcknowledgedAt != nil else { return false }
        guard deliveries[index].processingRetryStartedAt != nil else { return true }
        deliveries[index].attemptGeneration = nil
        if let error {
            let now = Date().timeIntervalSince1970 * 1000
            guard let deadline = DeliveryOutboxPolicy.terminalDeadline(
                for: deliveries[index]
            ), now < deadline else {
                let failedOriginSessionId = localOriginSessionId(for: deliveries[index])
                deliveries[index].state = .failed
                deliveries[index].error = L("No terminal response arrived from the computer.")
                deliveries[index].updatedAt = now
                deliveries[index].nextRetryAt = nil
                deliveries[index].processingAcknowledgedAt = nil
                deliveries[index].processingRetryStartedAt = nil
                persistDeliveries()
                if let failedOriginSessionId {
                    failDeferredFollowUps(forLocalSessionId: failedOriginSessionId)
                }
                pushToWatch()
                return true
            }
            guard attempt < maxDeliveryAttempts else {
                deliveries[index].error = nil
                deliveries[index].state = .sending
                deliveries[index].nextRetryAt = nil
                persistDeliveries()
                scheduleProcessingExpiry(id, at: deadline)
                return true
            }
            let delay = delays[min(max(0, attempt - 1), delays.count - 1)]
            let retryAt = now + delay * 1_000
            guard retryAt < deadline else {
                deliveries[index].error = nil
                deliveries[index].state = .sending
                deliveries[index].nextRetryAt = nil
                persistDeliveries()
                scheduleProcessingExpiry(id, at: deadline)
                return true
            }
            deliveries[index].error = error.localizedDescription
            deliveries[index].state = .queued
            deliveries[index].nextRetryAt = retryAt
            persistDeliveries()
            scheduleRecoveryTransportRetry(
                id,
                attempt: attempt,
                at: retryAt,
                before: deadline
            )
            return true
        }
        deliveries[index].error = nil
        deliveries[index].state = .sending
        deliveries[index].nextRetryAt = nil
        persistDeliveries()
        return true
    }

    func deliveryAttemptFinished(
        _ id: String,
        error: Error?,
        generation: String? = nil,
        receiptRetryDelay: TimeInterval = 20,
        transportRetryDelays: [TimeInterval] = [2, 5, 15, 30, 60]
    ) {
        guard let index = deliveries.firstIndex(where: { $0.id == id }),
              deliveries[index].state != .delivered else { return }
        if let generation {
            liveDeliveryAttemptGenerations.remove(generation)
            guard deliveries[index].attemptGeneration == generation else { return }
        } else if deliveries[index].attemptGeneration != nil {
            return
        }
        let attempt = deliveries[index].attempts
        let delays = transportRetryDelays

        // An authenticated processing ack is stronger than a late transport
        // callback. Its persisted provider/lease deadline exclusively owns the
        // next transition, so neither success nor error may shorten it.
        // A callback from the pre-ack send is advisory only. Recovery-send
        // callbacks retain the persisted provider deadline in the helper.
        if finishAcknowledgedAttempt(
            at: index,
            id: id,
            error: error,
            attempt: attempt,
            delays: delays
        ) { return }

        deliveries[index].attemptGeneration = nil

        // WebSocket write succeeded — wait for delivery.receipt instead of
        // immediately re-queuing (that looked like endless "Queued 1/2…").
        if error == nil {
            let retryAt = (Date().timeIntervalSince1970 + receiptRetryDelay) * 1000
            deliveries[index].error = nil
            deliveries[index].state = .sending
            deliveries[index].nextRetryAt = retryAt
            persistDeliveries()
            DispatchQueue.main.asyncAfter(deadline: .now() + receiptRetryDelay) { [weak self] in
                guard let self, let idx = self.deliveries.firstIndex(where: { $0.id == id }) else { return }
                let current = self.deliveries[idx]
                guard current.state == .sending,
                      current.processingAcknowledgedAt == nil,
                      current.attempts == attempt,
                      current.nextRetryAt == retryAt else { return }
                if self.outboxRowLooksDelivered(current) {
                    self.deliveries.remove(at: idx)
                    self.persistDeliveries()
                    return
                }
                self.deliveries[idx].state = .queued
                self.attemptDelivery(id)
            }
            return
        }

        if attempt >= maxDeliveryAttempts, outboxRowLooksDelivered(deliveries[index]) {
            deliveries.remove(at: index)
            persistDeliveries()
            return
        }

        let delay = delays[min(max(0, attempt - 1), delays.count - 1)]
        deliveries[index].state = attempt >= maxDeliveryAttempts ? .failed : .queued
        deliveries[index].error = error?.localizedDescription
        deliveries[index].nextRetryAt = deliveries[index].state == .queued
            ? (Date().timeIntervalSince1970 + delay) * 1000 : nil
        persistDeliveries()
        guard deliveries[index].state == .queued else {
            if let failedOriginSessionId = localOriginSessionId(for: deliveries[index]) {
                failDeferredFollowUps(forLocalSessionId: failedOriginSessionId)
            }
            AuditStore.shared.record("delivery", detail: "Automatic retries exhausted", outcome: "failed")
            pruneStaleDeliveries()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let current = self.deliveries.first(where: { $0.id == id }),
                  current.state == .queued, current.attempts == attempt else { return }
            self.attemptDelivery(id)
        }
    }

    func scheduleRecoveryTransportRetry(
        _ id: String,
        attempt: Int,
        at retryAt: Double,
        before deadline: Double
    ) {
        let delay = max(0, (retryAt - Date().timeIntervalSince1970 * 1000) / 1_000)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  let current = self.deliveries.first(where: { $0.id == id }),
                  current.state == .queued,
                  current.processingAcknowledgedAt != nil,
                  current.processingRetryStartedAt != nil,
                  current.attempts == attempt,
                  current.attemptGeneration == nil,
                  current.nextRetryAt == retryAt,
                  DeliveryOutboxPolicy.terminalDeadline(for: current) == deadline,
                  Date().timeIntervalSince1970 * 1000 >= retryAt,
                  Date().timeIntervalSince1970 * 1000 < deadline,
                  current.roomId.map(self.deliveryRoomIsUp) == true else { return }
            self.attemptDelivery(id)
        }
    }

    func reconcileInterruptedRecoveryAttempt(_ id: String) {
        guard let index = deliveries.firstIndex(where: { $0.id == id }),
              deliveries[index].state == .sending,
              deliveries[index].processingAcknowledgedAt != nil,
              deliveries[index].processingRetryStartedAt != nil,
              let generation = deliveries[index].attemptGeneration,
              !liveDeliveryAttemptGenerations.contains(generation) else { return }
        deliveries[index].attemptGeneration = nil
        if deliveries[index].attempts < maxDeliveryAttempts {
            deliveries[index].state = .queued
            deliveries[index].nextRetryAt = nil
        }
        persistDeliveries()
        if deliveries[index].state == .queued,
           deliveries[index].roomId.map(deliveryRoomIsUp) == true {
            attemptDelivery(id)
        }
    }

    /// True when the chat already reflects a successful send (receipt optional).
    func outboxRowLooksDelivered(_ d: OutgoingDelivery) -> Bool {
        guard let sid = d.sessionId else { return false }
        if let room = d.roomId, let preferred = connectionRegistry.preferredId,
           room != preferred { return false }
        let resolved = resolvedSessionId(sid)
        let entries = activities[resolved]?.entries
            ?? activities[sid]?.entries
            ?? []
        let text = d.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if entries.contains(where: {
            $0.id == "local-user-\(d.id)" || $0.id.hasPrefix("local-user-\(d.id)-")
        }) {
            if text.isEmpty { return true }
            if entries.contains(where: {
                ($0.kind == "user" || $0.kind == "message")
                    && $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == text
                    && !$0.id.hasPrefix("local-user-")
            }) { return true }
        }
        guard !text.isEmpty else { return false }
        return entries.contains(where: {
            ($0.kind == "user" || $0.kind == "message")
                && $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == text
                && !$0.id.hasPrefix("local-user-")
        })
    }

    func persistDeliveries() { DeliveryPersistence.save(deliveries) }
}
