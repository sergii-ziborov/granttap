import XCTest
@testable import GrantTap

final class ReplicaStorageTests: XCTestCase {
    @MainActor
    func testOfflinePictureReadUsesTheDurableCopyWithoutAnyRelay() async throws {
        let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==")!
        let model = AppModel()
        let id = UUID().uuidString
        defer { ReplicaImageStore.shared.clear() }
        try ReplicaImageStore.shared.save(bytes, scope: "local-mac", sessionId: id, imageId: "photo")
        XCTAssertTrue(model.relaysByRoom.isEmpty)
        let restored = try await model.messageImageData(sessionId: id, imageId: "photo")
        XCTAssertEqual(restored, bytes)
        XCTAssertNotNil(MessageImageLoader.thumbnail(restored))
    }

    @MainActor
    func testLosingTheNodeKeepsAlreadyReceivedChatsReadable() {
        let model = AppModel()
        let pairing = Pairing(relayUrl: "ws://127.0.0.1:1", room: "offline-room", role: "phone",
            deviceName: "Test", senderId: "test-controller",
            myPublicKey: Data(repeating: 1, count: 32).base64EncodedString(),
            mySecretKey: Data(repeating: 2, count: 32).base64EncodedString(),
            peerPublicKey: Data(repeating: 3, count: 32).base64EncodedString())
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: pairing)
        let session = SessionInfo(sessionId: "received", agent: "codex", state: "idle",
            startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        model.sessions = [session]
        model.sessionHistory = [session]
        model.activities = [session.sessionId: SessionActivity(sessionId: session.sessionId,
            agent: "codex", state: "idle", entries: [.init(id: "first", kind: "user",
                text: "Cached", createdAt: 1)], generatedAt: 2)]
        model.purgeStalePreferredCatalogIfNeeded()
        XCTAssertEqual(model.sessions.map(\.sessionId), [session.sessionId])
        XCTAssertEqual(model.sessionHistory.map(\.sessionId), [session.sessionId])
        XCTAssertEqual(model.activities[session.sessionId]?.entries.first?.text, "Cached")
    }

    func testOriginalPicturesAndPageRoutesSurviveRestartAndStayScoped() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ReplicaImageStore(directory: directory)
        defer { store.clear() }
        let bytes = Data([1, 2, 3])
        let job = ReplicaImageJob(sessionId: "../chat", imageId: "../../image", cursor: "page-one")
        store.remember(job, scope: "machine-a")
        store.remember(.init(sessionId: job.sessionId, imageId: job.imageId, cursor: "wrong-oldest"), scope: "machine-a")
        try store.save(bytes, scope: "machine-a", sessionId: job.sessionId, imageId: job.imageId)
        let reopened = ReplicaImageStore(directory: directory)
        XCTAssertEqual(reopened.load(scope: "machine-a", sessionId: job.sessionId, imageId: job.imageId), bytes)
        XCTAssertEqual(reopened.cursor(scope: "machine-a", sessionId: job.sessionId, imageId: job.imageId), "page-one")
        XCTAssertNil(reopened.load(scope: "machine-b", sessionId: job.sessionId, imageId: job.imageId))
        XCTAssertNil(reopened.load(scope: "machine-a", sessionId: "other", imageId: job.imageId))
        XCTAssertGreaterThan(reopened.bytes, 0)
        XCTAssertThrowsError(try store.save(Data(), scope: "a", sessionId: "b", imageId: "c"))
        reopened.clear()
        XCTAssertEqual(reopened.bytes, 0)
        XCTAssertNil(reopened.cursor(scope: "machine-a", sessionId: job.sessionId, imageId: job.imageId))
    }

    func testCatalogKeepsReceivedChatsWhenAnotherComputerPublishes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        func chat(_ id: String) -> SessionInfo {
            SessionInfo(sessionId: id, agent: "codex", state: "idle", startedAt: 1,
                        lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        }
        let first = (0..<180).map { chat("chat-\($0)") }
        SessionCatalogCache.save(.init(sessions: first, history: [], machine: "A", tokensRecent: 0,
            tokenWindowHours: 12, generatedAt: 1), storageDirectory: folder)
        SessionCatalogCache.save(.init(sessions: [chat("machine-b")], history: [], machine: "B", tokensRecent: 0,
            tokenWindowHours: 12, generatedAt: 2), storageDirectory: folder)
        let restored = try XCTUnwrap(SessionCatalogCache.load(storageDirectory: folder))
        XCTAssertEqual(restored.sessions.map(\.sessionId), ["machine-b"])
        XCTAssertEqual(Set(restored.history.map(\.sessionId)), Set(first.map(\.sessionId)))
        SessionCatalogCache.clear(storageDirectory: folder)
        XCTAssertNil(SessionCatalogCache.load(storageDirectory: folder))
    }

    @MainActor
    func testClearRemovesEveryReplicaButKeepsDeviceIdentityAndOutbox() throws {
        let model = AppModel()
        let previousAccount = GrantTapAccountAPI.session
        let account = GrantTapAccountSession(accountId: "offline-cache-account",
                                            token: String(repeating: "t", count: 43))
        XCTAssertTrue(KeychainPairing.save(try JSONEncoder().encode(account),
                                           service: "com.ziborov.granttap.account-session"))
        defer {
            if let previousAccount, let data = try? JSONEncoder().encode(previousAccount) {
                _ = KeychainPairing.save(data, service: "com.ziborov.granttap.account-session")
            } else { GrantTapAccountAPI.clearSession() }
        }
        let previousOutbox = DeliveryPersistence.load()
        defer { DeliveryPersistence.save(previousOutbox) }
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty,
            pairing: PairingFixture.pairing(room: "retained-pairing"))
        let now = Date().timeIntervalSince1970 * 1_000
        model.deliveries = [.init(id: "retained-send", text: "Queued", agent: "codex", cwd: nil,
            sessionId: "offline", requestId: nil, roomId: "retained-pairing", attachments: [],
            preferredMcp: nil, skill: nil, createdAt: now, updatedAt: now, attempts: 0,
            state: .queued, error: nil, nextRetryAt: nil)]
        DeliveryPersistence.save(model.deliveries)
        let originalRegistry = model.connectionRegistry
        let originalDeliveries = model.deliveries
        let activity = SessionActivity(sessionId: "offline", agent: "claude", state: "idle",
            entries: [.init(id: "local-user-one", kind: "user", text: "Saved", createdAt: 1)], generatedAt: 1)
        model.applyActivity(activity)
        let snapshot = ProjectMeshSnapshot(type: "mesh.snapshot", sessionId: "mesh", projectId: "mesh",
            project: .init(projectId: "mesh", name: "Saved Mesh", repositoryRoot: "/test", canonicalRepositoryId: "example/mesh", createdAt: 1),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1)
        model.meshSnapshots = ["mesh": snapshot]
        model.persistMeshState()
        try ReplicaImageStore.shared.save(Data([1]), scope: "local-mac", sessionId: "offline", imageId: "photo")
        XCTAssertNotNil(ProjectMeshPersistence.load().snapshots["mesh"])
        XCTAssertGreaterThan(LocalReplicaCache.bytes, 0)
        let generation = model.replicaGeneration
        model.clearLocalSessionCache()
        XCTAssertNotEqual(generation, model.replicaGeneration)
        XCTAssertTrue(SessionActivityPersistence.load().isEmpty)
        XCTAssertTrue(ProjectMeshPersistence.load().snapshots.isEmpty)
        XCTAssertEqual(ReplicaImageStore.shared.bytes, 0)
        XCTAssertEqual(GrantTapAccountAPI.session?.accountId, account.accountId)
        XCTAssertEqual(GrantTapAccountAPI.session?.token, account.token)
        XCTAssertEqual(model.connectionRegistry, originalRegistry)
        XCTAssertEqual(model.deliveries.map(\.id), originalDeliveries.map(\.id))
        XCTAssertEqual(DeliveryPersistence.load().map(\.id), originalDeliveries.map(\.id))
    }
}
