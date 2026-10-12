import Foundation

@MainActor
final class ReplicaImageTransfer {
    struct Pending {
        let request: SessionImageRequest
        let room: String
        let continuation: CheckedContinuation<SessionImageChunk, Error>
    }
    private var pending: [String: Pending] = [:]

    func data(sessionId: String, imageId: String, cursor: String?, client: RelayClient) async throws -> Data {
        var data = Data()
        var length: Int?
        var mime: String?
        repeat {
            try Task.checkCancellation()
            let request = SessionImageRequest(sessionId: sessionId, requestId: UUID().uuidString,
                imageId: imageId, offset: data.count, historyCursor: cursor,
                createdAt: Date().timeIntervalSince1970 * 1_000)
            let chunk = try await receiveChunk(request, client: client)
            guard chunk.isWellFormed, chunk.unavailable != true,
                  let bytes = chunk.dataBase64.flatMap({ Data(base64Encoded: $0) }),
                  length == nil || length == chunk.totalBytes,
                  mime == nil || mime == chunk.mimeType else { throw TransferError.invalid }
            length = chunk.totalBytes
            mime = chunk.mimeType
            data.append(bytes)
        } while data.count < (length ?? 0)
        return data
    }

    private func receiveChunk(_ request: SessionImageRequest, client: RelayClient) async throws -> SessionImageChunk {
        try await withCheckedThrowingContinuation { continuation in
            pending[request.requestId] = Pending(request: request, room: client.pairing.room,
                                                 continuation: continuation)
            client.sendSession(payload: request, sessionId: request.sessionId, ttl: 20) { [weak self] error in
                guard let error else { return }
                Task { @MainActor in self?.fail(request.requestId, error: error) }
            }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                self?.fail(request.requestId, error: TransferError.timeout)
            }
        }
    }

    func receive(_ chunk: SessionImageChunk, fromRoom room: String) {
        guard let expected = pending[chunk.requestId], expected.room == room,
              expected.request.sessionId == chunk.sessionId,
              expected.request.imageId == chunk.imageId,
              expected.request.offset == chunk.offset, chunk.isWellFormed else { return }
        pending.removeValue(forKey: chunk.requestId)
        expected.continuation.resume(returning: chunk)
    }

    func cancel() {
        let requests = pending.values
        pending.removeAll()
        for request in requests { request.continuation.resume(throwing: CancellationError()) }
    }

    private func fail(_ id: String, error: Error) {
        pending.removeValue(forKey: id)?.continuation.resume(throwing: error)
    }

    enum TransferError: Error { case timeout, invalid, unavailable }
}
