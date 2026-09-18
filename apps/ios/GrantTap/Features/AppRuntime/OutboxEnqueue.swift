import Foundation
import SwiftUI
import UIKit

extension AppModel {
    private func finishMessageAdmission(
        _ admission: DeliveryPersistence.Admission,
        messageId: String,
        mcpReply: Bool,
        stubId: String?,
        effectiveAgent: String,
        text: String,
        attachments: [UserAttachment],
        createdAt: Double,
        awaitingSessionRemap: Bool,
        sourceRoom: String?,
        isNewTask: Bool,
        requestedAgent: String?
    ) {
        deliveries = admission.deliveries
        persistDeliveries()
        if admission.shouldSend, !mcpReply, let stubId {
            appendLocalChatEntry(
                sessionId: stubId,
                agent: effectiveAgent,
                entryId: "local-user-\(messageId)",
                kind: "user",
                text: text,
                createdAt: createdAt,
                attachments: attachments.map(\.name)
            )
        }
        if admission.shouldSend {
            if awaitingSessionRemap {
                append("outbox.deferred id=\(messageId.prefix(8)) awaiting native session")
            } else if sourceRoom.map(deliveryRoomIsUp) != true {
                append("outbox.queued id=\(messageId.prefix(8)) computer offline")
            } else {
                attemptDelivery(messageId)
            }
            append("me: \(text)")
            AuditStore.shared.record(
                "message",
                detail: mcpReply
                    ? "MCP ask reply"
                    : (isNewTask ? "New \(requestedAgent ?? "codex") task" : "Message queued for task")
            )
        } else {
            append("outbox.reject id=\(messageId.prefix(8)) capacity")
            AuditStore.shared.record(
                "delivery", detail: "Reliable outbox admission rejected", outcome: "failed"
            )
        }
        pushToWatch()
        if isNewTask { sessionToOpen = stubId }
    }

    func sendMessage(_ text: String, agent: String? = nil, cwd: String? = nil,
                     sessionId: String? = nil, requestId: String? = nil,
                     attachments: [UserAttachment] = [], attachmentRefs: [UserAttachmentRef] = [],
                     preferredMcp: String? = nil,
                     skill: String? = nil, roomId: String? = nil,
                     overrides: TurnOverrides = .unchanged) {
        // Reclaim only terminal/expired rows before evaluating admission.
        // Active lifecycles are protected by DeliveryPersistence.admit.
        pruneStaleDeliveries()
        let now = Date().timeIntervalSince1970 * 1000
        let messageId = UUID().uuidString.lowercased()
        // Any non-empty requestId is an MCP ask reply: retain its exact session
        // scope, but never mint a chat stub or attach agent/cwd (which could
        // spawn a separate "yes" task).
        let rawCorrelatedId = requestId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let correlatedId = rawCorrelatedId.flatMap { $0.isEmpty ? nil : $0 }
        let mcpReply = correlatedId != nil
        // Remap open-sheet stub ids → Mac ids so follow-ups APPEND, not "session not found".
        let exactRequestSession = sessionId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedIncoming = mcpReply
            ? exactRequestSession.flatMap { $0.isEmpty ? nil : $0 }
            : sessionId.map { resolvedSessionId($0) }
        let sourceRoom: String? = {
            if let correlatedId { return requestSourceRoom[correlatedId] }
            if let resolvedIncoming {
                // `self.` is required: the local `sourceRoom` constant shadows the
                // method name here, and Xcode 26's Swift resolves the bare call to
                // the String? constant ("cannot call value of non-function type").
                return self.sourceRoom(forSessionId: resolvedIncoming)
            }
            if let requestedRoom = roomId?.trimmingCharacters(in: .whitespacesAndNewlines),
               !requestedRoom.isEmpty {
                return requestedRoom
            }
            return connectionRegistry.preferredId
        }()
        let isNewTask = !mcpReply && resolvedIncoming == nil
        let awaitingSessionRemap = !mcpReply
            && resolvedIncoming.map { localOnlySessionIds.contains($0) } == true
            && deliveries.contains { delivery in
                delivery.sessionId == resolvedIncoming
                    && delivery.awaitingSessionRemap != true
                    && delivery.admissionRejected != true
                    && (delivery.state == .queued || delivery.state == .sending)
            }
        let effectiveAgent = AgentIdentity.normalize(
            agent
                ?? resolvedIncoming.flatMap { sid in
                    knownSession(for: sid, preferredAgent: nil)?.agent
                }
                ?? "codex"
        )
        // Only send what this provider can act on; anything else is dropped
        // here rather than travelling as a value the computer would ignore.
        let routedRoom: String? = {
            if isNewTask, let pinned = pinnedEndpointId(forWorkspace: cwd ?? "") { return pinned }
            return sourceRoom
        }()
        let advertised = advertisedModels(
            for: effectiveAgent, sessionId: resolvedIncoming, computerId: routedRoom
        )
        let wire = overrides.wire(for: effectiveAgent, advertised: advertised)
        let resolvedOverrides = (
            model: wire.model, permissionMode: wire.permissionMode, effort: wire.effort
        )

        let stubId: String? = mcpReply ? nil : ensureLocalSession(
            sessionId: resolvedIncoming,
            agent: effectiveAgent,
            cwd: cwd,
            title: text.isEmpty ? nil : String(text.prefix(80)),
            at: now
        )
        if let routedRoom, let stubId {
            rememberSessionSourceRoom(routedRoom, sessionId: stubId)
        }
        let candidate = OutgoingDelivery(
            id: messageId, text: text,
            // Persist the canonical provider for retries and existing-session
            // follow-ups too. Native session UUIDs are not globally unique
            // across providers, so sessionId alone is not a safe route key.
            agent: mcpReply ? nil : effectiveAgent,
            cwd: mcpReply ? nil : (isNewTask ? cwd : nil),
            sessionId: mcpReply ? resolvedIncoming : stubId,
            requestId: correlatedId, roomId: routedRoom,
            attachments: attachments,
            // Only what went ahead to this very room can be named there.
            attachmentRefs: attachmentRefs.isEmpty ? nil : attachmentRefs,
            preferredMcp: mcpReply ? nil : preferredMcp, skill: mcpReply ? nil : skill,
            // An MCP ask reply is an answer, not a new turn: it must not carry
            // a model or a permission mode of its own.
            model: mcpReply ? nil : resolvedOverrides.model,
            permissionMode: mcpReply ? nil : resolvedOverrides.permissionMode,
            effort: mcpReply ? nil : resolvedOverrides.effort,
            createdAt: now, updatedAt: now,
            attempts: 0, state: .queued, error: nil, nextRetryAt: nil,
            awaitingSessionRemap: awaitingSessionRemap
        )
        let admission = DeliveryPersistence.admit(candidate, into: deliveries)
        finishMessageAdmission(
            admission, messageId: messageId, mcpReply: mcpReply,
            stubId: stubId, effectiveAgent: effectiveAgent, text: text,
            attachments: attachments, createdAt: now,
            awaitingSessionRemap: awaitingSessionRemap, sourceRoom: routedRoom,
            isNewTask: isNewTask, requestedAgent: agent
        )
    }

    /// The row this receipt is about, or nothing.
    ///
    /// A receipt is only about a row that this phone sent, from the room it
    /// was sent to, in the chat it was sent for. Anything else is another
    /// computer's answer arriving here, and it changes nothing.
    private func deliveryRow(for receipt: DeliveryReceipt, fromRoom room: String) -> Int? {
        // Match case-insensitively — older monitors may echo UUID casing differently.
        let mid = receipt.messageId.lowercased()
        guard let index = deliveries.firstIndex(where: { $0.id.lowercased() == mid }) else {
            pruneStaleDeliveries()
            return nil
        }
        if let pinnedRoom = deliveries[index].roomId, pinnedRoom != room {
            append("receipt room mismatch ignored: \(receipt.messageId.prefix(8))")
            return nil
        }
        if deliveries[index].roomId == nil {
            // Authenticated receipt safely migrates a legacy persisted row.
            deliveries[index].roomId = room
        }
        if let receiptSession = receipt.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !receiptSession.isEmpty {
            let rowSession = deliveries[index].sessionId.map { resolvedSessionId($0) }
            guard rowSession == receiptSession else {
                append("receipt session mismatch ignored: \(receipt.messageId.prefix(8))")
                return nil
            }
        }
        return index
    }

    /// What an `accepted` receipt means, which is less than it sounds.
    ///
    /// A reply to an MCP question is finished when the waiter takes it. A chat
    /// message is not: `accepted` says the computer is working on it, so the
    /// row stays retryable until the agent's own event arrives. The first ack
    /// resets transport attempts; a duplicate keeps the same deadline.
    private func acceptDelivery(at index: Int, observedAt: Double) -> (retryAt: Double?, expiryAt: Double?) {
        let row = deliveries[index]
        // A correlated MCP question stays visible until the source Mac has
        // durably accepted the reply. Removing it at enqueue time loses the
        // only retry affordance when that room is offline or was unlinked.
        if let requestId = row.requestId, !requestId.isEmpty {
            questions.removeAll { $0.requestId == requestId }
            if !pending.contains(where: { $0.requestId == requestId }) {
                NotificationManager.shared.clear(requestId)
            }
        }
        AuditStore.shared.record("delivery", detail: "Message delivered to computer")
        if let requestId = row.requestId, !requestId.isEmpty {
            deliveries.remove(at: index)
            return (nil, nil)
        }
        if deliveries[index].processingAcknowledgedAt == nil {
            deliveries[index].processingAcknowledgedAt = observedAt
            deliveries[index].processingRetryStartedAt = nil
            deliveries[index].attempts = 0
        }
        deliveries[index].attemptGeneration = nil
        deliveries[index].updatedAt = observedAt
        deliveries[index].state = .sending
        deliveries[index].error = nil
        var retryAt: Double?
        if deliveries[index].processingRetryStartedAt == nil,
           let acknowledgedAt = deliveries[index].processingAcknowledgedAt {
            let next = deliveries[index].nextRetryAt
                ?? acknowledgedAt + DeliveryOutboxPolicy.processingRetryDelayMs
            deliveries[index].nextRetryAt = next
            retryAt = next
        } else {
            // The single provider-timeout retry has already begun.
            deliveries[index].nextRetryAt = nil
        }
        return (retryAt, DeliveryOutboxPolicy.terminalDeadline(for: deliveries[index]))
    }

    /// The computer refused the message, or never got what it named.
    private func failDelivery(at index: Int, receipt: DeliveryReceipt, observedAt: Double) {
        deliveries[index].updatedAt = observedAt
        deliveries[index].nextRetryAt = nil
        deliveries[index].state = .failed
        deliveries[index].error = receipt.error ?? L("The computer rejected this message.")
        deliveries[index].processingAcknowledgedAt = nil
        deliveries[index].processingRetryStartedAt = nil
        deliveries[index].attemptGeneration = nil
        AuditStore.shared.record("delivery", detail: "Message rejected by computer", outcome: "failed")
    }

    func receive(_ receipt: DeliveryReceipt, fromRoom room: String) {
        // A member's message was never in this outbox; its receipt is theirs.
        if handOffReceiptToMember(receipt) { return }
        guard let index = deliveryRow(for: receipt, fromRoom: room) else { return }
        let row = deliveries[index]
        if let generation = deliveries[index].attemptGeneration {
            liveDeliveryAttemptGenerations.remove(generation)
        }
        let observedAt = Date().timeIntervalSince1970 * 1000
        var schedule: (retryAt: Double?, expiryAt: Double?) = (nil, nil)
        if receipt.status == "accepted" {
            schedule = acceptDelivery(at: index, observedAt: observedAt)
        } else if receipt.error == AttachmentUploads.missingError, deliveries[index].attachmentRefs != nil {
            // The attachment the message named never reached the computer: the
            // same message goes again with the bytes inside it.
            deliveries[index].attachmentRefs = nil
            deliveries[index].updatedAt = observedAt
            deliveries[index].attemptGeneration = nil
            append("outbox.inline id=\(row.id.prefix(8)) attachments resent inline")
            persistDeliveries()
            retryDelivery(row.id)
            return
        } else {
            failDelivery(at: index, receipt: receipt, observedAt: observedAt)
        }
        persistDeliveries()
        if receipt.status != "accepted", let sessionId = localOriginSessionId(for: row) {
            failDeferredFollowUps(forLocalSessionId: sessionId)
        }
        pruneStaleDeliveries()
        if let retryAt = schedule.retryAt {
            scheduleProcessingRetry(receipt.messageId, at: retryAt)
        }
        if let expiryAt = schedule.expiryAt {
            scheduleProcessingExpiry(receipt.messageId, at: expiryAt)
        }
        pushToWatch()
    }

    /// Clear outbox rows outside their bounded delivery window or already in the transcript.
}
