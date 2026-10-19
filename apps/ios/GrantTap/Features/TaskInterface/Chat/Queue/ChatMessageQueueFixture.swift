#if DEBUG
import Foundation

enum ChatMessageQueueFixture {
    @MainActor static func apply(to model: AppModel, at now: Double) {
        guard ProcessInfo.processInfo.environment["GRANTTAP_DEMO"] == "1",
              ["1", "failed", "relay", "delivery-failed", "legacy-sent"].contains(ProcessInfo.processInfo.environment["GRANTTAP_TEST_CHAT_QUEUE"]),
              let session = model.sessions.first(where: {
                  $0.sessionId == AppModelDemoFixtures.codexSessionId
              }) else { return }
        model.pending = []
        model.questions = []
        model.deliveries = (1...3).map { index in
            OutgoingDelivery(id: "queue-\(index)", text: "Queued follow-up \(index)",
                agent: session.agent, cwd: nil, sessionId: session.sessionId, requestId: nil,
                roomId: model.sourceRoom(forSessionId: session.sessionId),
                attachments: index == 1 ? [UserAttachment(name: "Queue.txt", mimeType: "text/plain",
                    data: Data("Queued attachment\n".utf8).base64EncodedString())] : [],
                preferredMcp: nil, skill: nil, projectId: session.projectId,
                createdAt: now + Double(index), updatedAt: now,
                attempts: 0, state: .queued, error: nil, nextRetryAt: nil,
                chatQueue: ChatMessageQueueContext(waiting: true, transport: .relay,
                                                   taskId: session.taskId))
        }
        if ProcessInfo.processInfo.environment["GRANTTAP_TEST_CHAT_QUEUE"] == "relay" {
            model.deliveries = Array(model.deliveries.prefix(1))
            let room = model.deliveries[0].roomId ?? "queue-demo-room"
            if !model.connectionRegistry.connections.contains(where: { $0.id == room }) {
                let pairing = Pairing(relayUrl: "wss://relay.test", room: room, role: "phone",
                    deviceName: "Fixture", senderId: "fixture", myPublicKey: "",
                    mySecretKey: "", peerPublicKey: "")
                model.connectionRegistry = ConnectionRegistryLogic.upsert(model.connectionRegistry, pairing: pairing)
            }
            model.sessionSourceRooms[session.sessionId] = [room]
            model.deliveries[0].roomId = room
            model.deliveries[0].chatQueue?.relayManaged = true
            model.deliveries[0].relayJob = RelayTaskQueueReservation(jobId: "queue-1", token: nil,
                notBefore: now, expiresAt: now + 86_400_000, createdAt: now,
                uploadAttempted: true, serverState: .queued)
            if let index = model.connectionRegistry.connections.firstIndex(where: {
                $0.id == model.deliveries[0].roomId
            }) { model.connectionRegistry.connections[index].taskQueueImmediate = true }
        }
        if ProcessInfo.processInfo.environment["GRANTTAP_TEST_CHAT_QUEUE"] == "failed" {
            model.deliveries = Array(model.deliveries.prefix(1))
            model.deliveries[0].state = .failed
            model.deliveries[0].attempts = 5
            model.deliveries[0].chatQueue?.waiting = false
            model.deliveries[0].error = L("Delivery was not confirmed after five attempts.")
        }
        if ProcessInfo.processInfo.environment["GRANTTAP_TEST_CHAT_QUEUE"] == "delivery-failed" {
            model.deliveries = Array(model.deliveries.prefix(1))
            model.deliveries[0].chatQueue = nil
            model.deliveries[0].state = .failed
            model.deliveries[0].error = L("No terminal response arrived from the computer.")
            model.appendQueuedMessageToTranscript(model.deliveries[0])
        }
        if ProcessInfo.processInfo.environment["GRANTTAP_TEST_CHAT_QUEUE"] == "legacy-sent" {
            model.deliveries = Array(model.deliveries.prefix(1))
            model.deliveries[0].chatQueue?.waiting = false
            model.deliveries[0].state = .sending
            model.deliveries[0].attempts = 1
        }
    }
}
#endif
