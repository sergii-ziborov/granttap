import Foundation

@MainActor
extension AppModel {
    func requestRelayTaskQueueRestart(_ id: String) {
        guard let index = deliveries.firstIndex(where: { $0.id == id }),
              ChatMessageQueuePolicy.canCancel(deliveries[index]) else { return }
        let now = floor(Date().timeIntervalSince1970 * 1_000)
        let state = deliveries[index].relayJob?.serverState
        if (state == nil || state == .queued),
           (deliveries[index].chatQueue?.notBefore ?? 0) <= now {
            // An unconfirmed upload may already be committing. Retrying its
            // immutable envelope preserves exactly-once admission and FIFO.
            deliveries[index].error = nil
            deliveries[index].nextRetryAt = nil
            persistDeliveries()
            resumeRelayTaskQueues(immediate: true)
            return
        }
        deliveries[index].chatQueue?.cancelRequested = true
        deliveries[index].chatQueue?.restartAfterCancellation = true
        persistDeliveries()
        resumeRelayTaskQueues(immediate: true)
    }

    func reconcileRelayTaskQueueCancellation(_ id: String, transport: RelayTaskQueueTransport) async throws {
        guard let index = deliveries.firstIndex(where: { $0.id == id }) else { return }
        guard let reservation = deliveries[index].relayJob, reservation.uploadAttempted == true else {
            finishRelayTaskQueueCancellation(at: index)
            return
        }
        if reservation.serverState == nil {
            // Resolve an ambiguous upload before cancelling. A 404 alone cannot
            // exclude an older upload still committing at the server.
            applyRelayTaskQueueReceipt(try await transport.upload(reservation), to: id)
        }
        let receipt = try await transport.receipt(id)
        if receipt.state == .expired || receipt.state == .cancelled {
            if let current = deliveries.firstIndex(where: { $0.id == id }) {
                finishRelayTaskQueueCancellation(at: current)
            }
        } else if receipt.state == .accepted || receipt.state == .completed {
            applyRelayTaskQueueReceipt(receipt, to: id)
            if let current = deliveries.firstIndex(where: { $0.id == id }) {
                deliveries[current].chatQueue?.cancelRequested = false
                deliveries[current].chatQueue?.restartAfterCancellation = false
                if receipt.state == .accepted {
                    setRelayTaskQueueError(id, L("The computer already accepted this task. Open its chat to stop it."))
                } else { persistDeliveries() }
            }
        } else {
            applyRelayTaskQueueReceipt(try await transport.cancel(id), to: id)
        }
    }

    func finishRelayTaskQueueCancellation(at index: Int) {
        let row = deliveries.remove(at: index)
        Task.detached(priority: .utility) { RelayTaskQueueCipherStore.remove(row.id) }
        if row.chatQueue?.restartAfterCancellation == true {
            let now = floor(Date().timeIntervalSince1970 * 1_000)
            let replacement = OutgoingDelivery(id: UUID().uuidString.lowercased(), text: row.text,
                agent: row.agent, cwd: row.cwd, sessionId: row.sessionId, requestId: nil, roomId: row.roomId,
                attachments: row.attachments, preferredMcp: row.preferredMcp, skill: row.skill,
                projectId: row.projectId, model: row.model, permissionMode: row.permissionMode, effort: row.effort,
                createdAt: now, updatedAt: now, attempts: 0, state: .queued, error: nil, nextRetryAt: nil,
                chatQueue: ChatMessageQueueContext(waiting: true, transport: row.chatQueue?.transport ?? .relay, taskId: row.chatQueue?.taskId,
                    queuedAt: now, relayManaged: true, notBefore: now))
            deliveries = DeliveryPersistence.admit(replacement, into: deliveries).deliveries
            relayQueueNeedsSync = true
        }
        persistDeliveries()
    }
}

enum RelayTaskQueueStatus {
    static func title(_ row: OutgoingDelivery) -> String? {
        guard row.chatQueue?.relayManaged == true else { return nil }
        if row.chatQueue?.cancelRequested == true { return L("Waiting for relay cancellation") }
        return switch row.relayJob?.serverState {
        case .none: L("Saving to relay…")
        case .queued: L("Saved on relay")
        case .accepted: L("Accepted by computer")
        case .completed: L("Delivered")
        case .failed: L("Needs attention")
        case .cancelled: L("Cancelled")
        case .expired: L("Expired")
        }
    }

    static func failure(_ receipt: RelayTaskJobReceipt) -> String? {
        if receipt.state == .expired { return L("The queued task expired without starting.") }
        guard receipt.state == .failed else { return nil }
        return switch receipt.resultCode {
        case "confirmation_required": L("Delivery was interrupted. Check the chat before retrying.")
        case "policy_denied": L("The computer's current policy does not allow this queued task.")
        case "provider_unavailable": L("The selected provider is unavailable on this computer.")
        default: L("The computer could not complete delivery. Check the chat before retrying.")
        }
    }
}
