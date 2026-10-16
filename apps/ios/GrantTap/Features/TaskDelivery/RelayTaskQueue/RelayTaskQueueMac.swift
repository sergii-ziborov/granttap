#if targetEnvironment(macCatalyst)
import Foundation

@MainActor
extension AppModel {
    func synchronizeLocalRelayTaskQueue(_ id: String) async throws {
        guard let index = deliveries.firstIndex(where: { $0.id == id }),
              let reader = localMCPReader, reader.isReady else { throw RelayTaskQueueError.unavailable }
        let row = deliveries[index]
        if row.chatQueue?.cancelRequested == true, row.relayJob?.uploadAttempted != true {
            finishRelayTaskQueueCancellation(at: index)
            return
        }
        if row.relayJob == nil {
            let created = floor(row.chatQueue?.queuedAt ?? row.createdAt)
            let due = floor(row.chatQueue?.notBefore ?? row.createdAt)
            deliveries[index].relayJob = RelayTaskQueueReservation(jobId: id, token: nil,
                notBefore: due, expiresAt: min(created + 30 * 86_400_000, due + 7 * 86_400_000),
                createdAt: created, envelope: nil)
        }
        let action = row.chatQueue?.cancelRequested == true ? "cancel"
            : row.relayJob?.serverState == nil ? "put" : "status"
        if action == "put" { deliveries[index].relayJob?.uploadAttempted = true; persistDeliveries() }
        let receipt = try await reader.queuedTask(deliveries[index], action: action)
        applyRelayTaskQueueReceipt(receipt, to: id)
        if action == "cancel", receipt.state == .accepted || receipt.state == .completed,
           let current = deliveries.firstIndex(where: { $0.id == id }) {
            deliveries[current].chatQueue?.cancelRequested = false
            deliveries[current].chatQueue?.restartAfterCancellation = false
            if receipt.state == .accepted {
                setRelayTaskQueueError(id, L("The computer already accepted this task. Open its chat to stop it."))
            } else { persistDeliveries() }
        }
    }
}
#endif
