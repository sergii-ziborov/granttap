import XCTest
@testable import GrantTap

@MainActor
final class ReplicaImageTransferTests: XCTestCase {
    private func client() -> RelayClient {
        RelayClient(pairing: Pairing(relayUrl: "ws://127.0.0.1:1", room: "test-room",
            role: "phone", deviceName: "Test", senderId: "test-controller",
            myPublicKey: Data(repeating: 1, count: 32).base64EncodedString(),
            mySecretKey: Data(repeating: 2, count: 32).base64EncodedString(),
            peerPublicKey: Data(repeating: 3, count: 32).base64EncodedString()))
    }

    private func request(_ client: RelayClient, offset: Int) async throws -> SessionImageRequest {
        for _ in 0..<200 {
            if let request = client.pendingSessionPayloads.values.compactMap({
                try? JSONDecoder().decode(SessionImageRequest.self, from: $0.plain)
            }).first(where: { $0.offset == offset }) { return request }
            await Task.yield()
        }
        throw ReplicaImageTransfer.TransferError.timeout
    }

    func testChunksAssembleOnlyForTheExactComputerConversationAndRequest() async throws {
        let client = client(), broker = ReplicaImageTransfer()
        defer { client.disconnect(); broker.cancel() }
        let job = Task { try await broker.data(sessionId: "chat", imageId: "photo", cursor: "page", client: client) }
        let first = try await request(client, offset: 0)
        let bytes = Data(repeating: 7, count: 65_537)
        func chunk(_ request: SessionImageRequest, sessionId: String = "chat") -> SessionImageChunk {
            .init(type: "session.image.chunk", sessionId: sessionId, requestId: request.requestId,
                imageId: "photo", offset: request.offset, mimeType: "image/png", totalBytes: bytes.count,
                dataBase64: bytes.subdata(in: request.offset..<min(request.offset + 65_536, bytes.count)).base64EncodedString(),
                unavailable: nil)
        }
        broker.receive(chunk(first), fromRoom: "another-computer")
        broker.receive(chunk(first, sessionId: "another-chat"), fromRoom: "test-room")
        broker.receive(chunk(first), fromRoom: "test-room")
        let second = try await request(client, offset: 65_536)
        XCTAssertEqual(second.historyCursor, "page")
        broker.receive(chunk(second), fromRoom: "test-room")
        let assembled = try await job.value
        XCTAssertEqual(assembled, bytes)
    }

    func testClearingCacheCancelsAnUnfinishedImageTransfer() async throws {
        let client = client(), broker = ReplicaImageTransfer()
        defer { client.disconnect() }
        let job = Task { try await broker.data(sessionId: "chat", imageId: "photo", cursor: nil, client: client) }
        _ = try await request(client, offset: 0)
        broker.cancel()
        do { _ = try await job.value; XCTFail("Cancelled transfer succeeded") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testMalformedOrUnavailableChunksCannotBecomeAnImage() {
        let valid = SessionImageChunk(type: "session.image.chunk", sessionId: "chat", requestId: "id",
            imageId: "photo", offset: 0, mimeType: "image/png", totalBytes: 3, dataBase64: "AQID", unavailable: nil)
        XCTAssertTrue(valid.isWellFormed)
        let bad = SessionImageChunk(type: valid.type, sessionId: valid.sessionId, requestId: valid.requestId,
            imageId: valid.imageId, offset: -1, mimeType: valid.mimeType, totalBytes: 3, dataBase64: "AQID", unavailable: nil)
        XCTAssertFalse(bad.isWellFormed)
        let unavailable = SessionImageChunk(type: valid.type, sessionId: valid.sessionId, requestId: valid.requestId,
            imageId: valid.imageId, offset: 0, mimeType: nil, totalBytes: nil, dataBase64: nil, unavailable: true)
        XCTAssertTrue(unavailable.isWellFormed)
    }
}
