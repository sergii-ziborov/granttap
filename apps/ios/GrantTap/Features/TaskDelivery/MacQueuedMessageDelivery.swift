#if targetEnvironment(macCatalyst)
import Foundation

extension AppModel {
    func resumeLocalQueuedDeliveries() {
        for row in deliveries where row.chatQueue?.transport == .localMCP
            && row.chatQueue?.waiting == false
            && (row.state == .queued || row.state == .sending) {
            attemptDelivery(row.id)
        }
    }

    func attemptLocalQueuedDelivery(_ id: String) {
        guard let index = deliveries.firstIndex(where: { $0.id == id }),
              deliveries[index].state == .queued || deliveries[index].state == .sending else { return }
        let row = deliveries[index]
        if let generation = row.attemptGeneration,
           liveDeliveryAttemptGenerations.contains(generation) { return }
        guard row.attempts == 0 else {
            deliveries[index].state = .failed
            deliveries[index].error = L("Delivery was interrupted. Check the chat before retrying.")
            persistDeliveries()
            return
        }
        guard let reader = localMCPReader, reader.isReady else { return }
        guard let sessionId = row.sessionId, let deliveryId = UUID(uuidString: row.id),
              let session = knownSession(for: sessionId, preferredAgent: row.agent),
              session.projectId == row.projectId, session.taskId == row.chatQueue?.taskId,
              row.preferredMcp == nil, row.skill == nil else {
            deliveries[index].state = .failed
            deliveries[index].error = L("The queued message no longer has an available Task route.")
            persistDeliveries()
            return
        }
        let attachments = row.attachments.compactMap { attachment -> AttachmentDraft? in
            guard let data = Data(base64Encoded: attachment.data) else { return nil }
            return AttachmentDraft(name: attachment.name, mimeType: attachment.mimeType, data: data)
        }
        guard attachments.count == row.attachments.count else { return }
        let generation = UUID().uuidString
        deliveries[index].attemptGeneration = generation
        deliveries[index].attempts = 1
        deliveries[index].state = .sending
        liveDeliveryAttemptGenerations.insert(generation)
        persistDeliveries()
        Task {
            do {
                let result = try await reader.send(row.text, to: session, attachments: attachments,
                                                   deliveryId: deliveryId, model: row.model)
                completeLocalChatQueue(id, generation: generation,
                                       accepted: result.accepted, error: result.error)
            } catch {
                completeLocalChatQueue(id, generation: generation, accepted: false,
                    error: L("Delivery was interrupted. Check the chat before retrying."))
            }
        }
    }

    func completeLocalChatQueue(_ id: String, generation: String,
                               accepted: Bool, error: String?) {
        liveDeliveryAttemptGenerations.remove(generation)
        guard let index = deliveries.firstIndex(where: { $0.id == id }),
              deliveries[index].attemptGeneration == generation else { return }
        deliveries[index].state = accepted ? .delivered : .failed
        deliveries[index].updatedAt = Date().timeIntervalSince1970 * 1_000
        deliveries[index].attemptGeneration = nil
        deliveries[index].error = accepted ? nil : error ?? L("Could not send to this Task.")
        persistDeliveries()
        // A fresh catalog, rather than the pre-send idle snapshot, releases the
        // next follow-up. This also works when its chat is no longer open.
    }
}
#endif
