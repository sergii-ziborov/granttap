import XCTest
@testable import GrantTap

@MainActor
final class HistoricalImageRouteTests: XCTestCase {
    func testOfflineOpeningDoesNotDiscardAValidHistoricalLocator() async {
        let model = AppModel()
        model.demoMode = true
        model.connectionRegistry = .empty
        model.sessionSourceRooms = [:]
        model.relaysByRoom = [:]
        let session = UUID().uuidString
        let store = ReplicaImageStore.shared
        store.remember(.init(sessionId: session, imageId: "photo", cursor: "good-page"), scope: "local-mac")
        defer { store.forgetCursor(scope: "local-mac", sessionId: session, imageId: "photo") }
        do {
            _ = try await model.messageImageData(sessionId: session, imageId: "photo")
            XCTFail("An uncached offline picture is unavailable")
        } catch {
            XCTAssertEqual(store.cursor(scope: "local-mac", sessionId: session, imageId: "photo"), "good-page")
        }
    }

    func testAnUnavailableOldCursorIsDiscardedAndTheSamePictureRecoversByIdentity() async throws {
        let pairing = Pairing(relayUrl: "ws://127.0.0.1:1", room: "stale-picture-room", role: "phone",
            deviceName: "Test", senderId: "test-controller",
            myPublicKey: Data(repeating: 1, count: 32).base64EncodedString(),
            mySecretKey: Data(repeating: 2, count: 32).base64EncodedString(),
            peerPublicKey: Data(repeating: 3, count: 32).base64EncodedString())
        let model = AppModel(), client = RelayClient(pairing: pairing)
        model.demoMode = true
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: pairing)
        model.relaysByRoom = [pairing.room: client]
        model.sessionSourceRooms = ["stale-chat": [pairing.room]]
        defer { client.disconnect(); model.replicaImageTransfer.cancel(); ReplicaImageStore.shared.clear() }
        let store = ReplicaImageStore.shared
        store.remember(.init(sessionId: "stale-chat", imageId: "photo", cursor: "expired-page"), scope: pairing.room)
        let read = Task { try await model.messageImageData(sessionId: "stale-chat", imageId: "photo") }
        func pending(excluding: String? = nil) async -> SessionImageRequest? {
            for _ in 0..<500 {
                let request = client.pendingSessionPayloads.values.compactMap {
                    try? JSONDecoder().decode(SessionImageRequest.self, from: $0.plain)
                }.first { $0.requestId != excluding }
                if let request { return request }
                await Task.yield()
            }
            return nil
        }
        let original = await pending()
        let first = try XCTUnwrap(original)
        XCTAssertEqual(first.historyCursor, "expired-page")
        model.replicaImageTransfer.receive(.init(type: "session.image.chunk", sessionId: first.sessionId,
            requestId: first.requestId, imageId: first.imageId, offset: 0, mimeType: nil,
            totalBytes: nil, dataBase64: nil, unavailable: true), fromRoom: pairing.room)
        let next = await pending(excluding: first.requestId)
        let recovered = try XCTUnwrap(next)
        XCTAssertNil(recovered.historyCursor)
        XCTAssertNil(store.cursor(scope: pairing.room, sessionId: "stale-chat", imageId: "photo"))
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==")!
        model.replicaImageTransfer.receive(.init(type: "session.image.chunk", sessionId: recovered.sessionId,
            requestId: recovered.requestId, imageId: recovered.imageId, offset: 0, mimeType: "image/png",
            totalBytes: png.count, dataBase64: png.base64EncodedString(), unavailable: nil), fromRoom: pairing.room)
        let bytes = try await read.value
        XCTAssertEqual(bytes, png)
    }

    func testHistoricalReadUsesItsOwnPageInsteadOfTheMergedCursorAndThenWorksOffline() async throws {
        let pairing = Pairing(relayUrl: "ws://127.0.0.1:1", room: "historical-picture-room", role: "phone",
            deviceName: "Test", senderId: "test-controller",
            myPublicKey: Data(repeating: 1, count: 32).base64EncodedString(),
            mySecretKey: Data(repeating: 2, count: 32).base64EncodedString(),
            peerPublicKey: Data(repeating: 3, count: 32).base64EncodedString())
        let model = AppModel(), client = RelayClient(pairing: pairing)
        model.demoMode = true
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: pairing)
        model.relaysByRoom = [pairing.room: client]
        model.sessionSourceRooms = ["historical-chat": [pairing.room]]
        defer {
            client.disconnect(); model.replicaImageTransfer.cancel()
            model.replicaImageTask?.cancel(); ReplicaImageStore.shared.clear()
        }
        let entry = ActivityEntry(id: "old-photo", kind: "user", text: "", createdAt: 1, attachments: ["Image"])
        let page = SessionActivity(sessionId: "historical-chat", agent: "codex", state: "idle",
            entries: [entry], generatedAt: 2,
            history: .init(cursor: "next-older", hasMore: true, requestedCursor: "picture-page"))
        let merged = SessionActivity(sessionId: page.sessionId, agent: page.agent, state: "idle",
            entries: [entry], generatedAt: 3,
            history: .init(cursor: "oldest", hasMore: true, requestedCursor: "unrelated-page"))
        model.replicaImageRetryAt[page.sessionId + "\u{0}" + entry.id] = Date().timeIntervalSince1970 + 60
        model.enqueueReplicaImages(page)
        model.enqueueReplicaImages(merged, rememberPageRoutes: false)
        let read = Task { try await model.messageImageData(sessionId: page.sessionId, imageId: entry.id) }
        var request: SessionImageRequest?
        for _ in 0..<500 where request == nil {
            request = client.pendingSessionPayloads.values.compactMap {
                try? JSONDecoder().decode(SessionImageRequest.self, from: $0.plain)
            }.first
            await Task.yield()
        }
        let query = try XCTUnwrap(request)
        XCTAssertEqual(query.historyCursor, "picture-page")
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==")!
        model.replicaImageTransfer.receive(.init(type: "session.image.chunk", sessionId: query.sessionId,
            requestId: query.requestId, imageId: query.imageId, offset: 0, mimeType: "image/png",
            totalBytes: png.count, dataBase64: png.base64EncodedString(), unavailable: nil), fromRoom: pairing.room)
        let received = try await read.value
        XCTAssertEqual(received, png)
        model.relaysByRoom = [:]
        let offline = try await model.messageImageData(sessionId: page.sessionId, imageId: entry.id)
        XCTAssertEqual(offline, received)
    }
}
