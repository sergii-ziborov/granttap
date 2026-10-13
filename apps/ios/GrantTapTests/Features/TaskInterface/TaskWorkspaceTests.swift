import XCTest
@testable import GrantTap

@MainActor
final class TaskWorkspaceTests: XCTestCase {
    private func client() -> RelayClient {
        RelayClient(pairing: Pairing(relayUrl: "ws://127.0.0.1:1", room: "fixture-room",
            role: "phone", deviceName: "Fixture", senderId: "fixture-controller",
            myPublicKey: Data(repeating: 1, count: 32).base64EncodedString(),
            mySecretKey: Data(repeating: 2, count: 32).base64EncodedString(),
            peerPublicKey: Data(repeating: 3, count: 32).base64EncodedString()))
    }

    private func query(_ id: String = UUID().uuidString, mode: String = "directory") -> TaskWorkspaceQuery {
        .init(sessionId: "fixture-chat", requestId: id, mode: mode, path: "src", offset: 0, createdAt: 1)
    }

    private func result(_ query: TaskWorkspaceQuery) -> TaskWorkspaceSnapshot {
        .init(type: "session.workspace.result", sessionId: query.sessionId, requestId: query.requestId,
            path: query.path, entries: [.init(path: "src/app.swift", name: "app.swift", kind: "file", size: 10)],
            truncated: false, createdAt: 2)
    }

    private func waitForRead(_ client: RelayClient) async {
        for _ in 0..<200 {
            if client.pendingSessionPayloads.values.contains(where: {
                (try? JSONDecoder().decode(TaskWorkspaceQuery.self, from: $0.plain)) != nil
            }) { return }
            await Task.yield()
        }
        XCTFail("Scoped workspace query was not sent")
    }

    func testOnlyTheMatchingRoomSessionPathAndRequestCanCompleteRead() async throws {
        let relay = client(), broker = TaskWorkspaceReadBroker(), query = query()
        defer { relay.disconnect(); broker.cancel() }
        let job = Task { try await broker.read(query, client: relay) }
        await waitForRead(relay)
        broker.receive(result(query), fromRoom: "foreign-room")
        var wrong = result(query)
        wrong = .init(type: wrong.type, sessionId: "foreign-chat", requestId: wrong.requestId,
            path: wrong.path, entries: wrong.entries, truncated: false, createdAt: 2)
        broker.receive(wrong, fromRoom: "fixture-room")
        broker.receive(result(self.query("foreign-request")), fromRoom: "fixture-room")
        broker.receive(result(query), fromRoom: "fixture-room")
        let received = try await job.value
        XCTAssertEqual(received.entries?.first?.path, "src/app.swift")
        broker.receive(received, fromRoom: "fixture-room") // duplicate cannot resume twice
    }

    func testAnAuthenticatedComputerResponseIsStoredBeforeOpeningItsFileAgainOffline() async throws {
        let model = AppModel(), relay = client()
        defer { relay.disconnect(); model.clearLocalSessionCache() }
        let session = SessionInfo(sessionId: "fixture-chat", agent: "codex", state: "idle",
            startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: relay.pairing)
        model.relaysByRoom[relay.pairing.room] = relay
        model.sessionSourceRooms[session.sessionId] = [relay.pairing.room]
        model.roomRuntime[relay.pairing.room] = .init(socketUp: true)
        let job = Task { try await model.readTaskWorkspace(for: session, mode: "file", path: "src/app.swift") }
        await waitForRead(relay)
        let query = try XCTUnwrap(relay.pendingSessionPayloads.values.compactMap {
            try? JSONDecoder().decode(TaskWorkspaceQuery.self, from: $0.plain)
        }.first)
        let snapshot = TaskWorkspaceSnapshot(type: "session.workspace.result", sessionId: query.sessionId,
            requestId: query.requestId, path: query.path, text: "let value = 42", truncated: false, createdAt: 2)
        model.taskWorkspaceReads.receive(snapshot, fromRoom: relay.pairing.room)
        let online = try await job.value
        XCTAssertEqual(online, snapshot)
        model.roomRuntime[relay.pairing.room]?.socketUp = false
        let offline = try await model.readTaskWorkspace(for: session, mode: "file", path: query.path)
        XCTAssertEqual(offline.text, snapshot.text)
        let identity = model.connectionRegistry
        model.clearLocalSessionCache()
        XCTAssertEqual(model.connectionRegistry, identity)
        XCTAssertEqual(model.connectionRegistry.connections.first?.pairing, relay.pairing)
    }

    func testTimeoutCancellationAndUnavailableResponsesEndLoading() async {
        let relay = client(), broker = TaskWorkspaceReadBroker()
        defer { relay.disconnect(); broker.cancel() }
        do {
            _ = try await broker.read(query(), client: relay, timeoutNanoseconds: 1_000_000)
            XCTFail("Missing computer response must time out")
        } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        let q = query(), job = Task { try await broker.read(q, client: relay) }
        await Task.yield()
        broker.cancel()
        do { _ = try await job.value; XCTFail("Cache clear must cancel reads") }
        catch { XCTAssertTrue(error is CancellationError) }
        let missing = query(), unavailable = Task { try await broker.read(missing, client: relay) }
        await Task.yield()
        broker.receive(.init(type: "session.workspace.result", sessionId: missing.sessionId,
            requestId: missing.requestId, path: missing.path, truncated: false,
            unavailable: true, createdAt: 2), fromRoom: "fixture-room")
        do { _ = try await unavailable.value; XCTFail("Missing files cannot become an empty directory") }
        catch { XCTAssertEqual((error as? URLError)?.code, .resourceUnavailable) }
    }

    func testDurablePreviewIsSeparatedByAccountComputerChatPathAndPage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = TaskWorkspaceStore(directory: directory), q = query(), snapshot = result(q)
        defer { store.clear() }
        store.save(snapshot, scope: "account:mac", mode: q.mode, offset: 0)
        XCTAssertEqual(store.load(scope: "account:mac", sessionId: q.sessionId, mode: q.mode,
                                  path: q.path, offset: 0), snapshot)
        for (scope, session, mode, path, offset) in [
            ("other:mac", q.sessionId, q.mode, q.path, 0),
            ("account:mac", "other-chat", q.mode, q.path, 0),
            ("account:mac", q.sessionId, "file", q.path, 0),
            ("account:mac", q.sessionId, q.mode, "other", 0),
            ("account:mac", q.sessionId, q.mode, q.path, 200)
        ] {
            XCTAssertNil(store.load(scope: scope, sessionId: session, mode: mode, path: path, offset: offset))
        }
        XCTAssertGreaterThan(store.bytes, 0)
        store.clear()
        XCTAssertEqual(store.bytes, 0)
    }

    func testPagedTextIsValidButTraversalMixedBodiesAndRepeatedPageOffsetsAreNot() {
        var preview = TaskWorkspaceSnapshot(type: "session.workspace.result", sessionId: "fixture-chat",
            requestId: "page", path: "src/file.swift", text: "let value = 42", truncated: true,
            nextOffset: 128_000, createdAt: 2)
        XCTAssertTrue(preview.isWellFormed)
        preview.nextOffset = 0
        XCTAssertFalse(preview.isWellFormed)
        preview.nextOffset = nil
        preview.entries = []
        XCTAssertFalse(preview.isWellFormed)
        let traversal = TaskWorkspaceSnapshot(type: "session.workspace.result", sessionId: "fixture-chat",
            requestId: "bad", path: "../private", text: "invalid", truncated: false, createdAt: 2)
        XCTAssertFalse(traversal.isWellFormed)
    }

    func testOfflineFilePreviewRemainsReadableAndClearPreservesConnectionIdentity() async throws {
        let model = AppModel(), q = query(mode: "file")
        let session = SessionInfo(sessionId: q.sessionId, agent: "codex", state: "idle",
            startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        let snapshot = TaskWorkspaceSnapshot(type: "session.workspace.result", sessionId: q.sessionId,
            requestId: q.requestId, path: q.path, text: "let value = 42", truncated: false, createdAt: 2)
        TaskWorkspaceStore.shared.save(snapshot, scope: model.imageStorageScope(q.sessionId), mode: "file", offset: 0)
        let identity = model.connectionRegistry
        let received = try await model.readTaskWorkspace(for: session, mode: "file", path: q.path)
        XCTAssertEqual(received.text, snapshot.text)
        XCTAssertNil(model.cachedTaskWorkspace(for: session, mode: "bad", path: q.path))
        model.clearLocalSessionCache()
        XCTAssertEqual(model.connectionRegistry, identity)
        XCTAssertNil(model.cachedTaskWorkspace(for: session, mode: "file", path: q.path))
        do { _ = try await model.readTaskWorkspace(for: session, mode: "file", path: q.path) }
        catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
    }
}
