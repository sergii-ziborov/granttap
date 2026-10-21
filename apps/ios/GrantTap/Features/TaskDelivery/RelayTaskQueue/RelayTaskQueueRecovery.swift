import Foundation

/// The relay owns accepted queue work; the local outbox is a recoverable view of it.
enum RelayTaskQueueRecovery {
    struct StoredJob: Decodable {
        let id: String
        let state: RelayTaskJobState
        let notBefore: Double
        let expiresAt: Double
        let envelope: Envelope
    }

    static func restore(_ stored: StoredJob, pairing: Pairing) -> OutgoingDelivery? {
        let envelope = stored.envelope
        guard envelope.v == 1, envelope.room == pairing.room, envelope.from == .phone,
              envelope.to == "machine", envelope.senderId == pairing.senderId,
              envelope.recipientKeyId == CiphertextRecipient.identifier(publicKey: pairing.peerPublicKey),
              envelope.deliveryId == stored.id,
              let plain = Crypto.open(nonceB64: envelope.nonce, boxB64: envelope.box,
                  theirPublicKeyB64: pairing.peerPublicKey, mySecretKeyB64: pairing.mySecretKey),
              let job = try? JSONDecoder().decode(RelayQueuedTask.self, from: plain),
              job.type == "task.dispatch", job.jobId == stored.id,
              job.notBefore == stored.notBefore, job.expiresAt == stored.expiresAt,
              job.expiresAt == envelope.expiresAt, job.operation.messageId == job.jobId,
              job.operation.sessionId == job.sessionId, job.operation.requestId == nil else { return nil }
        let message = job.operation
        let reservation = RelayTaskQueueReservation(jobId: job.jobId, token: job.token, notBefore: job.notBefore,
            expiresAt: job.expiresAt, createdAt: job.createdAt, envelope: envelope,
            uploadAttempted: true, serverState: stored.state)
        return OutgoingDelivery(id: stored.id, text: message.text, agent: message.agent, cwd: message.cwd,
            sessionId: message.sessionId, requestId: nil, roomId: pairing.room,
            attachments: message.attachments ?? [], preferredMcp: message.preferredMcp, skill: message.skill,
            projectId: message.projectId, model: message.model, permissionMode: message.permissionMode,
            effort: message.effort, createdAt: job.createdAt, updatedAt: job.createdAt, attempts: 0,
            state: stored.state == .accepted ? .sending : stored.state == .failed ? .failed : .queued,
            error: nil, nextRetryAt: nil, relayStoredAt: job.createdAt,
            chatQueue: ChatMessageQueueContext(waiting: true, transport: .relay, taskId: nil,
                queuedAt: job.createdAt, relayManaged: true, notBefore: job.notBefore,
                sendImmediately: job.deliveryMode == "immediate"), relayJob: reservation,
            taskOriginId: message.taskOriginId, continuationOriginId: message.originMessageId)
    }
}

@MainActor
extension AppModel {
    func restoreRelayTaskQueue(room: String, session: URLSession = .shared) async {
        guard let connection = connectionRegistry.connections.first(where: { $0.id == room }),
              !connection.pairing.isHub, connection.pairing.pushAuth != nil else { return }
        let transport = RelayTaskQueueTransport(pairing: connection.pairing,
            address: relaysByRoom[room]?.resolvedRelayURL, session: session)
        do {
            let jobs = try await transport.activeJobs()
            for receipt in jobs {
                guard connectionRegistry.connections.contains(where: { $0.id == room && $0.pairing == connection.pairing }) else { return }
                if let known = deliveries.first(where: { $0.id == receipt.id }) {
                    guard known.roomId == room else { continue }
                    applyRelayTaskQueueReceipt(receipt, to: receipt.id)
                    continue
                }
                guard !Task.isCancelled,
                      var row = RelayTaskQueueRecovery.restore(try await transport.storedJob(receipt.id),
                                                               pairing: connection.pairing),
                      !deliveries.contains(where: { $0.id == row.id }),
                      connectionRegistry.connections.contains(where: { $0.id == room && $0.pairing == connection.pairing }) else { continue }
                if let reservation = row.relayJob {
                    row.relayJob = try await Task.detached(priority: .utility) {
                        try RelayTaskQueueCipherStore.save(reservation)
                    }.value
                }
                deliveries.append(row)
                persistDeliveries()
            }
            resumeRelayTaskQueues()
        } catch {
            // A missing receipt never removes or resubmits an already retained operation.
        }
    }
}
