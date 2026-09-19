import Foundation
import SwiftUI
import UIKit

extension AppModel {
    private func failDelivery(at index: Int, message: String) {
        let failedOriginSessionId = localOriginSessionId(for: deliveries[index])
        deliveries[index].state = .failed
        deliveries[index].nextRetryAt = nil
        deliveries[index].attemptGeneration = nil
        deliveries[index].error = message
        persistDeliveries()
        if let failedOriginSessionId {
            failDeferredFollowUps(forLocalSessionId: failedOriginSessionId)
        }
    }

    func attemptDelivery(_ id: String) {
        guard let index = deliveries.firstIndex(where: { $0.id == id }),
              deliveries[index].state != .delivered,
              deliveries[index].admissionRejected != true,
              deliveries[index].awaitingSessionRemap != true else { return }

        if deliveries[index].roomId == nil {
            let migratedRoom = deliveries[index].requestId.flatMap { requestSourceRoom[$0] }
                ?? (connectionRegistry.connections.count == 1
                    ? connectionRegistry.connections.first?.id : nil)
            guard let migratedRoom else {
                failDelivery(
                    at: index,
                    message: L("Delivery cannot be routed safely because its source computer is unknown.")
                )
                return
            }
            deliveries[index].roomId = migratedRoom
            persistDeliveries()
        }

        guard let roomId = deliveries[index].roomId,
              connectionRegistry.connections.contains(where: { $0.id == roomId }) else {
            failDelivery(
                at: index,
                message: L("The source computer for this message was removed.")
            )
            return
        }
        guard deliveryRoomIsUp(roomId), relaysByRoom[roomId] != nil else {
            deliveries[index].state = .queued
            deliveries[index].error = nil
            deliveries[index].nextRetryAt = nil
            deliveries[index].attemptGeneration = nil
            persistDeliveries()
            return
        }
        guard deliveries[index].attempts < maxDeliveryAttempts else {
            // Prefer drop over false "undelivered" when chat already shows the send.
            if outboxRowLooksDelivered(deliveries[index]) {
                deliveries.remove(at: index)
                persistDeliveries()
                return
            }
            failDelivery(
                at: index,
                message: L("Delivery was not confirmed after five attempts.")
            )
            pruneStaleDeliveries()
            return
        }

        deliveries[index].attempts += 1
        deliveries[index].state = .sending
        deliveries[index].updatedAt = Date().timeIntervalSince1970 * 1000
        deliveries[index].error = nil
        deliveries[index].nextRetryAt = nil
        let attemptGeneration = UUID().uuidString.lowercased()
        deliveries[index].attemptGeneration = attemptGeneration
        liveDeliveryAttemptGenerations.insert(attemptGeneration)
        let delivery = deliveries[index]
        persistDeliveries()

        guard let relay = relaysByRoom[roomId] else {
            deliveryAttemptFinished(
                id,
                error: NSError(domain: "GrantTap", code: -1,
                               userInfo: [NSLocalizedDescriptionKey: L("Relay is offline.")]),
                generation: attemptGeneration
            )
            return
        }

        // Phone-minted stub UUIDs stay local and wire as a new task. Existing
        // chats retain their Mac id and always include the canonical provider.
        let localOnly = delivery.sessionId.map { localOnlySessionIds.contains($0) } ?? false
        let wire = wireUserMessage(for: delivery)
        append("outbox.wire id=\(delivery.id.prefix(8)) session=\(wire.sessionId?.prefix(8) ?? "new") agent=\(wire.agent ?? "-") localOnly=\(localOnly)")
        relay.sendMessage(wire.text, messageId: wire.messageId ?? delivery.id,
                          agent: wire.agent, cwd: wire.cwd,
                          sessionId: wire.sessionId, requestId: wire.requestId,
                          attachments: wire.attachments ?? [], attachmentRefs: wire.attachmentRefs ?? [],
                          preferredMcp: wire.preferredMcp,
                          skill: wire.skill, projectId: wire.projectId,
                          model: wire.model, permissionMode: wire.permissionMode,
                          effort: wire.effort) { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.append("outbox.fail id=\(id.prefix(8)) \(error.localizedDescription)")
                } else {
                    self?.append("outbox.sent id=\(id.prefix(8))")
                }
                self?.deliveryAttemptFinished(
                    id,
                    error: error,
                    generation: attemptGeneration
                )
            }
        }
    }

    func knownSession(
        for rawSessionId: String,
        preferredAgent: String?
    ) -> SessionInfo? {
        let resolved = resolvedSessionId(rawSessionId)
        let candidates = sessions
            + sessionHistory
            + Array(archivedSessions.values)
        let matchingIds = candidates.filter {
            $0.sessionId == rawSessionId || $0.sessionId == resolved
                || resolvedSessionId($0.sessionId) == resolved
        }
        if let preferredAgent {
            let normalized = AgentIdentity.normalize(preferredAgent)
            if let exact = matchingIds.first(where: {
                AgentIdentity.normalize($0.agent) == normalized
            }) {
                return exact
            }
        }
        return matchingIds.first
    }
}
