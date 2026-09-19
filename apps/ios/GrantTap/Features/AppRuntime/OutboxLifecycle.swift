import Foundation
import SwiftUI
import UIKit

extension AppModel {
    private func expireStaleDeliveries(
        in snapshot: inout [OutgoingDelivery],
        now: Double
    ) -> (transitioned: Bool, failedSessionIds: Set<String>) {
        var transitionedExpiredProcessing = false
        var failedOriginSessionIds: Set<String> = []
        for index in snapshot.indices {
            if let deadline = DeliveryOutboxPolicy.terminalDeadline(for: snapshot[index]),
               now > deadline {
                if let sessionId = localOriginSessionId(for: snapshot[index]) {
                    failedOriginSessionIds.insert(sessionId)
                }
                snapshot[index].state = .failed
                snapshot[index].error = L("No terminal response arrived from the computer.")
                snapshot[index].updatedAt = now
                snapshot[index].nextRetryAt = nil
                snapshot[index].processingAcknowledgedAt = nil
                snapshot[index].processingRetryStartedAt = nil
                if let generation = snapshot[index].attemptGeneration {
                    liveDeliveryAttemptGenerations.remove(generation)
                }
                snapshot[index].attemptGeneration = nil
                transitionedExpiredProcessing = true
            } else if snapshot[index].awaitingSessionRemap == true,
                      snapshot[index].state != .failed,
                      now - snapshot[index].createdAt
                        > DeliveryOutboxPolicy.maximumLocalRetentionMs {
                snapshot[index].state = .failed
                snapshot[index].error = L(
                    "The original task ended before a native session was created. Retry this message to start a new task."
                )
                snapshot[index].updatedAt = now
                snapshot[index].nextRetryAt = nil
                snapshot[index].attemptGeneration = nil
                transitionedExpiredProcessing = true
            } else if let sessionId = localOriginSessionId(for: snapshot[index]),
                      snapshot[index].state != .failed,
                      now - deferredLifecycleAnchor(for: snapshot[index])
                        > DeliveryOutboxPolicy.maximumLocalRetentionMs {
                failedOriginSessionIds.insert(sessionId)
                snapshot[index].state = .failed
                snapshot[index].error = L("Delivery was not confirmed after five attempts.")
                snapshot[index].updatedAt = now
                snapshot[index].nextRetryAt = nil
                snapshot[index].attemptGeneration = nil
                transitionedExpiredProcessing = true
            }
        }
        return (transitionedExpiredProcessing, failedOriginSessionIds)
    }

    private func shouldRetainDelivery(
        _ delivery: OutgoingDelivery,
        now: Double,
        maxUnacknowledgedAge: Double
    ) -> Bool {
        if delivery.state == .delivered {
            let awaitingOrigin = delivery.sessionId.map { localOnlySessionIds.contains($0) } == true
            let retainsImagePreview = delivery.attachments.contains {
                    $0.mimeType.hasPrefix("image/") && !$0.data.isEmpty
            }
            let retention = retainsImagePreview
                ? DeliveryOutboxPolicy.sentImagePreviewRetentionMs
                : DeliveryOutboxPolicy.terminalLifecycleMs
            return (awaitingOrigin || retainsImagePreview) && now - delivery.createdAt <= retention
        }
        if delivery.state == .queued, delivery.attempts == 0,
           delivery.processingAcknowledgedAt == nil {
            return now - delivery.createdAt <= TaskDeliveryQueue.retentionMilliseconds(for: delivery)
        }
        if delivery.awaitingSessionRemap == true,
           (delivery.state == .queued || delivery.state == .sending) {
            return now - delivery.createdAt <= DeliveryOutboxPolicy.maximumLocalRetentionMs
        }
        if localOriginSessionId(for: delivery) != nil,
           (delivery.state == .queued || delivery.state == .sending) {
            return now - deferredLifecycleAnchor(for: delivery)
                <= DeliveryOutboxPolicy.maximumLocalRetentionMs
        }
        if delivery.awaitingSessionRemap == false,
           delivery.processingAcknowledgedAt == nil,
           (delivery.state == .queued || delivery.state == .sending) {
            return now - delivery.updatedAt <= maxUnacknowledgedAge
        }
        if now - (delivery.state == .failed ? delivery.updatedAt : delivery.createdAt)
            > TaskDeliveryQueue.retentionMilliseconds(for: delivery),
           delivery.processingAcknowledgedAt == nil { return false }
        if let requestId = delivery.requestId, !requestId.isEmpty,
           !questions.contains(where: { $0.requestId == requestId }),
           !pending.contains(where: { $0.requestId == requestId }),
           now - delivery.createdAt > 15_000 { return false }
        guard let sessionId = delivery.sessionId else {
            return !(delivery.state == .failed && now - delivery.createdAt > 8_000)
        }
        let resolved = resolvedSessionId(sessionId)
        let sameRoom = delivery.roomId == nil || connectionRegistry.preferredId == nil
            || delivery.roomId == connectionRegistry.preferredId
        let entries = sameRoom ? (activities[resolved]?.entries ?? activities[sessionId]?.entries ?? []) : []
        let text = delivery.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasLocalBubble = entries.contains {
            $0.id == "local-user-\(delivery.id)" || $0.id.hasPrefix("local-user-\(delivery.id)-")
        }
        let hasMacEcho = !text.isEmpty && entries.contains {
            ($0.kind == "user" || $0.kind == "message")
                && $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == text
                && !$0.id.hasPrefix("local-user-")
        }
        let terminalTimeout = delivery.state == .failed
            && delivery.error == L("No terminal response arrived from the computer.")
        if delivery.processingAcknowledgedAt == nil, !terminalTimeout,
           hasLocalBubble && hasMacEcho { return false }
        if delivery.processingAcknowledgedAt == nil, !terminalTimeout,
           hasMacEcho, now - delivery.createdAt > 8_000 { return false }
        if delivery.state == .sending, delivery.processingAcknowledgedAt == nil,
           hasLocalBubble, now - delivery.createdAt > 45_000 { return false }
        if delivery.state == .failed, delivery.processingAcknowledgedAt == nil,
           !terminalTimeout, hasMacEcho { return false }
        return true
    }

    func pruneStaleDeliveries() {
        let now = Date().timeIntervalSince1970 * 1000
        let maxUnacknowledgedAge = DeliveryOutboxPolicy.unacknowledgedRetentionMs
        // Filter a snapshot so a no-op prune does not publish SwiftUI changes.
        var snapshot = deliveries
        let expiration = expireStaleDeliveries(in: &snapshot, now: now)
        let retainedCandidates = snapshot.filter {
            shouldRetainDelivery($0, now: now, maxUnacknowledgedAge: maxUnacknowledgedAge)
        }
        let retainedActiveCount = retainedCandidates.filter {
            $0.state == .queued || $0.state == .sending
        }.count
        let retainedCountBudget = retainedActiveCount > DeliveryPersistence.maxActiveCount
            ? retainedActiveCount + 1
            : DeliveryPersistence.maxPersistedCount
        let next = DeliveryPersistence.bounded(
            retainedCandidates,
            maxCount: retainedCountBudget
        )
        guard expiration.transitioned || next.count != deliveries.count else { return }
        liveDeliveryAttemptGenerations.formIntersection(
            Set(next.compactMap(\.attemptGeneration))
        )
        deliveries = next
        persistDeliveries()
        for sessionId in expiration.failedSessionIds {
            failDeferredFollowUps(forLocalSessionId: sessionId)
        }
    }

    /// Drop stuck MCP Yes/No outbox rows that block the chat UI after ack races.
    func clearStuckMcpReplies() {
        let before = deliveries.count
        deliveries.removeAll { delivery in
            guard let rid = delivery.requestId, !rid.isEmpty else { return false }
            return delivery.state == .delivered || delivery.state == .failed
                || delivery.attempts >= maxDeliveryAttempts
        }
        if deliveries.count != before { persistDeliveries() }
    }

    func retryDelivery(_ id: String) {
        guard let index = deliveries.firstIndex(where: { $0.id == id }),
              deliveries[index].admissionRejected != true,
              (deliveries[index].awaitingSessionRemap != true
                || deliveries[index].state == .failed) else { return }
        if let generation = deliveries[index].attemptGeneration {
            liveDeliveryAttemptGenerations.remove(generation)
        }
        deliveries[index].attempts = 0
        deliveries[index].state = .queued
        deliveries[index].error = nil
        deliveries[index].nextRetryAt = nil
        deliveries[index].processingAcknowledgedAt = nil
        deliveries[index].processingRetryStartedAt = nil
        deliveries[index].attemptGeneration = nil
        deliveries[index].updatedAt = Date().timeIntervalSince1970 * 1000
        // A dependency failure is explicitly retryable: promote this follow-up
        // to a fresh new-task origin. Provider identity is already persisted.
        if deliveries[index].awaitingSessionRemap == true {
            deliveries[index].awaitingSessionRemap = false
        }
        persistDeliveries()
        AuditStore.shared.record("delivery", detail: "Manual retry requested")
        attemptDelivery(id)
    }

    func deliveries(for sessionId: String?) -> [OutgoingDelivery] {
        // Keep a longer queue so rapid multi-send never drops earlier bubbles.
        // Include stub + remapped Mac id so double-send APPEND stays visible.
        guard let sessionId else { return [] }
        let resolved = resolvedSessionId(sessionId)
        var aliases: Set<String> = [sessionId, resolved]
        for (key, value) in sessionIdAliases {
            if value == resolved || key == sessionId || key == resolved {
                aliases.insert(key)
                aliases.insert(value)
            }
        }
        let now = Date().timeIntervalSince1970 * 1000
        let ownerRoom = sourceRoom(forSessionId: sessionId)
            ?? (connectionRegistry.connections.count == 1
                ? connectionRegistry.connections.first?.id : nil)
        return Array(deliveries.filter { delivery in
            if let room = delivery.roomId, room != ownerRoom { return false }
            guard let sid = delivery.sessionId else { return false }
            guard aliases.contains(sid) || resolvedSessionId(sid) == resolved else { return false }
            let isInsideRetentionWindow: Bool = {
                if delivery.state == .queued, delivery.attempts == 0,
                   delivery.processingAcknowledgedAt == nil {
                    return now - delivery.createdAt
                        <= TaskDeliveryQueue.retentionMilliseconds(for: delivery)
                }
                if delivery.awaitingSessionRemap == true,
                   (delivery.state == .queued || delivery.state == .sending) {
                    return now - delivery.createdAt
                        <= DeliveryOutboxPolicy.maximumLocalRetentionMs
                }
                if delivery.awaitingSessionRemap == false,
                   delivery.processingAcknowledgedAt == nil,
                   (delivery.state == .queued || delivery.state == .sending) {
                    return now - delivery.updatedAt
                        <= DeliveryOutboxPolicy.unacknowledgedRetentionMs
                }
                if let terminalDeadline = DeliveryOutboxPolicy.terminalDeadline(for: delivery) {
                    return now <= terminalDeadline
                }
                let ageAnchor = delivery.state == .failed
                    ? delivery.updatedAt : delivery.createdAt
                return now - ageAnchor < DeliveryOutboxPolicy.failedVisibilityMs
            }()
            switch delivery.state {
            case .delivered:
                return false // accept path removes these; never show ghosts
            case .queued, .sending:
                return isInsideRetentionWindow
            case .failed:
                return isInsideRetentionWindow
            }
        }.prefix(8))
    }

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
