import Foundation

@MainActor
extension AppModel {
    func attachReplicaReadCallbacks(_ client: RelayClient, room: String) {
        client.onImageChunk = { [weak self] chunk in
            guard let self, self.acceptsSessionPayload(sessionId: chunk.sessionId, fromRoom: room) else { return }
            self.replicaImageTransfer.receive(chunk, fromRoom: room)
        }
        client.onWorkspaceResult = { [weak self] result in
            guard let self, self.acceptsSessionPayload(sessionId: result.sessionId, fromRoom: room) else { return }
            self.taskWorkspaceReads.receive(result, fromRoom: room)
        }
    }
}
