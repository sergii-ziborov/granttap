import XCTest
@testable import GrantTap

@MainActor
final class ReplicaIntegrationTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==")!

    private func connectedModel() -> (AppModel, RelayClient) {
        let pairing = Pairing(relayUrl: "ws://127.0.0.1:1", room: "replica-test-room", role: "phone",
            deviceName: "Test", senderId: "test-controller",
            myPublicKey: Data(repeating: 1, count: 32).base64EncodedString(),
            mySecretKey: Data(repeating: 2, count: 32).base64EncodedString(),
            peerPublicKey: Data(repeating: 3, count: 32).base64EncodedString())
        let model = AppModel(), client = RelayClient(pairing: pairing)
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: pairing)
        model.relaysByRoom = [pairing.room: client]
        model.roomRuntime = [pairing.room: .init(socketUp: true)]
        model.sessionSourceRooms = [:]
        model.activities = [:]
        return (model, client)
    }

    private func chat(_ id: String) -> SessionInfo {
        SessionInfo(sessionId: id, agent: "codex", state: "idle", startedAt: 1,
                    lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
    }

    private func pictureActivity(_ id: String) -> SessionActivity {
        SessionActivity(sessionId: id, agent: "codex", state: "idle", entries: [
            .init(id: "picture", kind: "user", text: "Picture", createdAt: 1, attachments: ["Image"])
        ], generatedAt: 1, history: .init(cursor: "older", hasMore: true))
    }

    private func pendingImage(_ client: RelayClient) async throws -> SessionImageRequest {
        for _ in 0..<500 {
            if let request = client.pendingSessionPayloads.values.compactMap({
                try? JSONDecoder().decode(SessionImageRequest.self, from: $0.plain)
            }).first { return request }
            await Task.yield()
        }
        throw ReplicaImageTransfer.TransferError.timeout
    }

    func testAccountReconciliationRetainsTheRecoveredNameInMemoryAndOnDisk() {
        let previous = SessionCatalogCache.load()
        let (model, client) = connectedModel()
        defer {
            client.disconnect()
            SessionCatalogCache.clear()
            if let previous { SessionCatalogCache.save(previous, retainingPreviousHistory: false) }
        }
        let thin = chat("named-account-chat")
        var named = thin
        named.title = "Recovered conversation"
        model.sessions = [named]
        model.accountDeviceCatalogs = [client.pairing.room: .init(machine: "Test", sessions: [thin],
            history: [], tokensRecent: 0, tokenWindowHours: 12, generatedAt: 3)]
        model.refreshAccountDeviceCatalog()
        XCTAssertEqual(model.sessions.first?.displayTitle, named.displayTitle)
        XCTAssertEqual(SessionCatalogCache.load()?.sessions.first?.title, named.title)
    }

    func testStartupRestoresDurableCatalogWithoutStartingAnyTransport() {
        let previousRegistry = PairedConnectionStore.load()
        let previousCatalog = SessionCatalogCache.load()
        defer {
            _ = PairedConnectionStore.save(previousRegistry)
            SessionCatalogCache.clear()
            if let previousCatalog { SessionCatalogCache.save(previousCatalog, retainingPreviousHistory: false) }
        }
        let key = Data(repeating: 7, count: 32).base64EncodedString()
        let pairing = Pairing(relayUrl: "ws://127.0.0.1:1", room: String(repeating: "e", count: 32),
            role: "phone", deviceName: "Offline Mac", senderId: "offline-controller",
            myPublicKey: key, mySecretKey: key, peerPublicKey: key)
        let registry = ConnectionRegistryLogic.upsert(.empty, pairing: pairing)
        XCTAssertTrue(PairedConnectionStore.save(registry))
        var saved = chat("offline-startup-chat")
        saved.title = "Saved offline conversation"
        SessionCatalogCache.save(.init(sessions: [saved], history: [], machine: "Offline Mac",
            tokensRecent: 0, tokenWindowHours: 12, generatedAt: 1), retainingPreviousHistory: false)
        let model = AppModel()
        model.sessionSourceRooms = [saved.sessionId: [pairing.room]]
        model.restoreLocalReplica()
        XCTAssertEqual(model.pairing?.room, pairing.room)
        XCTAssertEqual(model.sessions.map(\.sessionId), [saved.sessionId])
        XCTAssertEqual(model.sessions.first?.title, saved.title)
        XCTAssertTrue(model.relaysByRoom.isEmpty)
        XCTAssertTrue(model.meshEndpointRelaysById.isEmpty)
        XCTAssertFalse(model.connected)
    }

    func testCatalogDrivenHistoryPersistsEveryPageWithoutOpeningAChat() {
        let (model, client) = connectedModel()
        defer { client.disconnect(); SessionActivityPersistence.clear() }
        model.sessions = [chat("a"), chat("b"), chat("c")]
        model.syncOfflineConversations()
        XCTAssertEqual(Set(model.transcriptBackfill.pending.keys), ["a", "b"])
        model.applyActivity(.init(sessionId: "a", agent: "codex", state: "idle", entries: [
            .init(id: "new", kind: "message", text: "Latest", createdAt: 2)
        ], generatedAt: 3, history: .init(cursor: "older", hasMore: true)), sourceNamespace: client.pairing.room)
        XCTAssertEqual(Set(model.transcriptBackfill.pending.keys), ["b", "c"])
        for id in ["b", "c"] {
            model.applyActivity(.init(sessionId: id, agent: "codex", state: "idle", entries: [],
                generatedAt: 3, history: .init(hasMore: false)), sourceNamespace: client.pairing.room)
        }
        XCTAssertEqual(model.transcriptBackfill.pending["a"]?.cursor, "older")
        model.applyActivity(.init(sessionId: "a", agent: "codex", state: "idle", entries: [
            .init(id: "old", kind: "user", text: "First", createdAt: 1)
        ], generatedAt: 4, history: .init(hasMore: false, requestedCursor: "older")),
            sourceNamespace: client.pairing.room)
        XCTAssertEqual(SessionActivityPersistence.load()["a"]?.entries.map(\.id), ["old", "new"])
        XCTAssertTrue(model.transcriptBackfill.pending.isEmpty)
        XCTAssertTrue(model.activitySubscribers.isEmpty)
    }

    func testIdenticalTranscriptRetainsItsFreshComputerReceiptAfterRestart() {
        let model = AppModel()
        model.connectionRegistry = .empty
        model.sessions = []
        model.activities = [:]
        defer { SessionActivityPersistence.clear() }
        let entry = ActivityEntry(id: "unchanged", kind: "user", text: "Saved request", createdAt: 1)
        let old = SessionActivity(sessionId: "receipt-test", agent: "codex", state: "idle",
            entries: [entry], generatedAt: 2, history: .init(hasMore: false))
        let fresh = SessionActivity(sessionId: old.sessionId, agent: old.agent, state: old.state,
            entries: old.entries, generatedAt: 10, history: old.history)
        model.applyActivity(old)
        model.applyActivity(fresh)
        XCTAssertEqual(model.activities[old.sessionId]?.generatedAt, 10)
        XCTAssertEqual(SessionActivityPersistence.load()[old.sessionId]?.generatedAt, 10)
        XCTAssertEqual(model.activities[old.sessionId]?.entries, [entry])
    }

    func testVerifiedPasskeyScopeRetainsPicturesSavedThroughTheSameQRRoute() async throws {
        let (model, client) = connectedModel()
        defer { client.disconnect(); ReplicaImageStore.shared.clear() }
        model.rememberSessionSourceRoom(client.pairing.room, sessionId: "qr-chat")
        try ReplicaImageStore.shared.save(png, scope: client.pairing.room, sessionId: "qr-chat", imageId: "picture")
        model.connectionRegistry.connections[0].accountCredential = .init(accountId: "account", machineId: "computer", machineToken: "test")
        XCTAssertEqual(model.imageStorageScope("qr-chat"), "account:computer")
        let bytes = try await model.messageImageData(sessionId: "qr-chat", imageId: "picture")
        XCTAssertEqual(bytes, png)
        XCTAssertEqual(ReplicaImageStore.shared.load(scope: "account:computer", sessionId: "qr-chat", imageId: "picture"), png)
    }

    func testPrefetchAndOpenShareOnePictureTransferAndRetainItOffline() async throws {
        let (model, client) = connectedModel()
        defer { client.disconnect(); model.replicaImageTransfer.cancel(); ReplicaImageStore.shared.clear() }
        model.rememberSessionSourceRoom(client.pairing.room, sessionId: "shared-picture-chat")
        let first = Task { try await model.messageImageData(sessionId: "shared-picture-chat", imageId: "same-photo") }
        let second = Task { try await model.messageImageData(sessionId: "shared-picture-chat", imageId: "same-photo") }
        let request = try await pendingImage(client)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(model.replicaImageReads.count, 1)
        XCTAssertEqual(client.pendingSessionPayloads.values.compactMap {
            try? JSONDecoder().decode(SessionImageRequest.self, from: $0.plain)
        }.filter { $0.imageId == "same-photo" }.count, 1)
        model.replicaImageTransfer.receive(.init(type: "session.image.chunk", sessionId: request.sessionId,
            requestId: request.requestId, imageId: request.imageId, offset: 0, mimeType: "image/png",
            totalBytes: png.count, dataBase64: png.base64EncodedString(), unavailable: nil), fromRoom: client.pairing.room)
        let bytes = try await first.value
        let other = try await second.value
        XCTAssertEqual(bytes, png)
        XCTAssertEqual(other, bytes)
        XCTAssertEqual(model.replicaImagesRevision, 1)
        model.relaysByRoom = [:]
        let offline = try await model.messageImageData(sessionId: request.sessionId, imageId: request.imageId)
        XCTAssertEqual(offline, bytes)
        XCTAssertTrue(model.replicaImageReads.isEmpty)
    }

    func testEncryptedPictureReplyIsValidatedThenSavedForOfflineUse() async throws {
        let (model, client) = connectedModel()
        defer { client.disconnect(); model.replicaImageTransfer.cancel(); ReplicaImageStore.shared.clear() }
        model.rememberSessionSourceRoom(client.pairing.room, sessionId: "chat")
        let transfer = Task { try await model.messageImageData(sessionId: "chat", imageId: "photo") }
        let request = try await pendingImage(client)
        model.replicaImageTransfer.receive(.init(type: "session.image.chunk", sessionId: "chat",
            requestId: request.requestId, imageId: "photo", offset: 0, mimeType: "image/png",
            totalBytes: png.count, dataBase64: png.base64EncodedString(), unavailable: nil), fromRoom: client.pairing.room)
        let received = try await transfer.value
        XCTAssertEqual(received, png)
        model.relaysByRoom = [:]
        let offline = try await model.messageImageData(sessionId: "chat", imageId: "photo")
        XCTAssertEqual(offline, received)
    }

    func testMissingPicturesBackOffAndCachedPicturesDoNotRefetch() async throws {
        let model = AppModel(), activity = pictureActivity("retry")
        model.connectionRegistry = .empty
        model.sessionSourceRooms = [:]
        model.relaysByRoom = [:]
        model.activities = [activity.sessionId: activity]
        defer { model.replicaImageTask?.cancel(); ReplicaImageStore.shared.clear() }
        XCTAssertEqual(model.imageConversation(forEntryId: "picture"), "retry")
        model.enqueueReplicaImages(activity)
        for _ in 0..<200 where model.replicaImageTask != nil { await Task.yield() }
        XCTAssertTrue(model.replicaImageQueue.isEmpty)
        XCTAssertNotNil(model.replicaImageRetryAt["retry\u{0}picture"])
        model.enqueueReplicaImages(activity)
        XCTAssertTrue(model.replicaImageQueue.isEmpty)
        try ReplicaImageStore.shared.save(png, scope: "local-mac", sessionId: "retry", imageId: "picture")
        model.replicaImageRetryAt = [:]
        model.enqueueReplicaImages(activity)
        XCTAssertTrue(model.replicaImageQueue.isEmpty)
        model.activities["other"] = pictureActivity("other")
        XCTAssertNil(model.imageConversation(forEntryId: "picture"))
        XCTAssertNil(model.imageConversation(forEntryId: "missing"))
    }

    func testCachedCatalogOmitsChatsFromAnotherAccount() {
        let (model, client) = connectedModel()
        let previous = SessionCatalogCache.load()
        defer {
            client.disconnect()
            SessionCatalogCache.clear()
            if let previous { SessionCatalogCache.save(previous, retainingPreviousHistory: false) }
        }
        model.sessionSourceRooms = ["mine": [client.pairing.room], "foreign": ["removed-room"]]
        SessionCatalogCache.save(.init(sessions: [], history: [chat("mine"), chat("foreign")],
            machine: "Test", tokensRecent: 0, tokenWindowHours: 12, generatedAt: 1),
            retainingPreviousHistory: false)
        model.loadReplicaCatalogIndex()
        XCTAssertEqual(Set(model.replicaSessionIndex.keys), ["mine"])
        model.sessions = []
        model.sessionHistory = []
        XCTAssertEqual(model.allSessionHistory.map(\.sessionId), ["mine"])
    }

    func testNowPrefetchSurvivesRestartAndOpensOfflineWithoutASubscription() {
        let previousRegistry = PairedConnectionStore.load()
        let previousCatalog = SessionCatalogCache.load()
        let (model, client) = connectedModel()
        defer {
            client.disconnect()
            SessionActivityPersistence.clear()
            _ = PairedConnectionStore.save(previousRegistry)
            SessionCatalogCache.clear()
            if let previousCatalog { SessionCatalogCache.save(previousCatalog, retainingPreviousHistory: false) }
        }
        let chats = [chat("now-a"), chat("now-b")]
        model.applySessionsStatus(.init(machine: "Test", sessions: chats, history: [],
            tokensRecent: 0, tokenWindowHours: 12, generatedAt: 3), fromRoom: client.pairing.room)
        XCTAssertEqual(Set(model.transcriptBackfill.pending.keys), Set(chats.map(\.sessionId)))
        for session in chats {
            model.applyActivity(.init(sessionId: session.sessionId, agent: "codex", state: "idle",
                entries: [.init(id: session.sessionId + "-latest", kind: "message", text: "Saved latest", createdAt: 2)],
                generatedAt: 3, history: .init(hasMore: false)), sourceNamespace: client.pairing.room)
        }
        XCTAssertTrue(model.activitySubscribers.isEmpty, "Now prefetch must not require opening a chat")
        client.disconnect()
        let reopened = AppModel()
        reopened.relaysByRoom = [:]
        reopened.sessions = chats
        for session in chats {
            let view = TaskChatView(session: session, modelOverride: reopened)
            XCTAssertEqual(view.entries.map(\.id), [session.sessionId + "-latest"])
            XCTAssertEqual(ChatTranscriptPhase.resolve(hasContent: !view.entries.isEmpty,
                connected: reopened.connected, snapshotKnown: view.activitySnapshotKnown), .content)
        }
        XCTAssertTrue(reopened.activitySubscribers.isEmpty)
        XCTAssertTrue(reopened.relaysByRoom.isEmpty)
    }
}
