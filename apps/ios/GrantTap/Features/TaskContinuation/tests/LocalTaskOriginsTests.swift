import XCTest
@testable import GrantTap

final class LocalTaskOriginsTests: XCTestCase {
    func testOriginSurvivesReloadAndIsScopedToComputerAndProvider() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        try LocalTaskOrigins.remember(sessionId: "stub", agent: "codex", room: "room", originId: "origin",
                                      at: 1_000, file: file)
        XCTAssertEqual(try LocalTaskOrigins.origin(sessionId: "stub", agent: "codex", room: "room",
                                                   now: 2_000, file: file), "origin")
        XCTAssertNil(try LocalTaskOrigins.origin(sessionId: "stub", agent: "grok", room: "room", now: 2_000, file: file))
        XCTAssertNil(try LocalTaskOrigins.origin(sessionId: "stub", agent: "codex", room: "other", now: 2_000, file: file))
        XCTAssertNil(try LocalTaskOrigins.origin(sessionId: "stub", agent: "codex", room: "room",
                                                 now: 38 * 86_400_000, file: file))
        XCTAssertThrowsError(try LocalTaskOrigins.remember(sessionId: "stub", agent: "codex", room: "room",
            originId: "changed", at: 2_000, file: file))
        try Data("broken".utf8).write(to: file)
        XCTAssertThrowsError(try LocalTaskOrigins.origin(sessionId: "stub", agent: "codex", room: "room",
                                                         now: 2_000, file: file))
    }
}

@MainActor
final class PendingTaskContinuationTests: XCTestCase {
    private func fixtureModel() -> AppModel {
        let model = AppModel()
        model.demoMode = true
        model.deliveries = []
        model.sessionIdAliases = [:]
        model.localOnlySessionIds = []
        let pairing = Pairing(relayUrl: "https://continuation.test", room: "fixture-room", role: "phone",
            deviceName: "Fixture", senderId: "fixture", myPublicKey: Data(repeating: 1, count: 32).base64EncodedString(),
            mySecretKey: Data(repeating: 2, count: 32).base64EncodedString(),
            peerPublicKey: Data(repeating: 3, count: 32).base64EncodedString())
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: pairing)
        return model
    }

    func testNewTaskFollowUpBecomesAnImmediateRelayJobBeforeNativeSessionExists() throws {
        let model = fixtureModel()
        model.sendMessage("Synthetic first task", agent: "grok", roomId: "fixture-room")
        let parent = try XCTUnwrap(model.deliveries.first)
        let stub = try XCTUnwrap(parent.sessionId)
        XCTAssertEqual(parent.taskOriginId, parent.id)
        model.sendMessage("Synthetic follow-up", agent: "grok", sessionId: stub)
        let child = try XCTUnwrap(model.deliveries.first { $0.text == "Synthetic follow-up" })
        XCTAssertEqual(child.continuationOriginId, parent.id)
        XCTAssertTrue(child.chatQueue?.relayManaged == true)
        XCTAssertTrue(child.chatQueue?.sendImmediately == true)
        XCTAssertEqual(child.awaitingSessionRemap, true)
        let message = model.relayQueuedMessage(for: child)
        XCTAssertEqual(message.type, "user.message.continue")
        XCTAssertEqual(message.originMessageId, parent.id)
        XCTAssertNil(message.sessionId)
        XCTAssertNil(message.cwd)
        let reloaded = try JSONDecoder().decode([OutgoingDelivery].self,
            from: JSONEncoder().encode(model.deliveries))
        XCTAssertEqual(reloaded.first { $0.id == child.id }?.continuationOriginId, parent.id)
    }

    func testNativeRemapKeepsRelayCiphertextAndReceiptMetadata() throws {
        let model = fixtureModel()
        model.sendMessage("Synthetic task", agent: "codex", roomId: "fixture-room")
        let stub = try XCTUnwrap(model.deliveries.first?.sessionId)
        model.sendMessage("Synthetic continuation", agent: "codex", sessionId: stub)
        let index = try XCTUnwrap(model.deliveries.firstIndex { $0.text == "Synthetic continuation" })
        let id = model.deliveries[index].id
        model.deliveries[index].relayStoredAt = 500
        model.deliveries[index].relayJob = .init(jobId: id, token: "token", notBefore: 1,
            expiresAt: 2_000, createdAt: 1, serverState: .queued)
        model.remapLocalSession(from: stub, to: "native-chat")
        let child = try XCTUnwrap(model.deliveries.first { $0.id == id })
        XCTAssertEqual(child.sessionId, "native-chat")
        XCTAssertEqual(child.relayStoredAt, 500)
        XCTAssertEqual(child.relayJob?.token, "token")
        XCTAssertNotNil(child.continuationOriginId)
        XCTAssertEqual(model.relayQueuedMessage(for: child).type, "user.message.continue")
    }

    func testExplicitQueueRestartPreservesItsDependencyOnTheOriginalTask() throws {
        let model = fixtureModel()
        model.sendMessage("Synthetic parent", agent: "claude", roomId: "fixture-room")
        let parent = try XCTUnwrap(model.deliveries.first)
        let chat = try XCTUnwrap(model.sessions.first { $0.sessionId == parent.sessionId })
        XCTAssertTrue(model.queueChatMessage("Synthetic queued continuation", to: chat))
        let index = try XCTUnwrap(model.deliveries.firstIndex { $0.chatQueue != nil })
        XCTAssertEqual(model.deliveries[index].continuationOriginId, parent.id)
        let previousID = model.deliveries[index].id
        model.deliveries[index].chatQueue?.restartAfterCancellation = true
        model.finishRelayTaskQueueCancellation(at: index)
        let replacement = try XCTUnwrap(model.deliveries.first { $0.chatQueue != nil })
        XCTAssertNotEqual(replacement.id, previousID)
        XCTAssertEqual(replacement.continuationOriginId, parent.id)
        XCTAssertTrue(replacement.awaitingSessionRemap == true)
        XCTAssertEqual(model.relayQueuedMessage(for: replacement).type, "user.message.continue")
    }

    func testRelayReceiptIsVisibleBeforeNativeRemapAndParentTimeoutDoesNotEraseIt() throws {
        let model = fixtureModel()
        model.sendMessage("Synthetic parent", agent: "cursor", roomId: "fixture-room")
        let parent = try XCTUnwrap(model.deliveries.first)
        model.sendMessage("Synthetic immediate continuation", agent: "cursor", sessionId: parent.sessionId)
        let index = try XCTUnwrap(model.deliveries.firstIndex { $0.continuationOriginId != nil })
        let id = model.deliveries[index].id
        model.deliveries[index].relayJob = .init(jobId: id, token: "token", notBefore: 1,
            expiresAt: 2_000, createdAt: 1)
        model.applyRelayTaskQueueReceipt(.init(id: id, state: .queued, notBefore: 1, expiresAt: 2_000,
                                              resultCode: nil), to: id)
        model.failDeferredFollowUps(forLocalSessionId: try XCTUnwrap(parent.sessionId))
        let saved = try XCTUnwrap(model.deliveries.first { $0.id == id })
        XCTAssertEqual(saved.state, .queued)
        XCTAssertNotNil(saved.relayStoredAt)
        XCTAssertEqual(RelayTaskQueueStatus.title(saved), L("Saved on relay"))
    }

    func testOriginMetadataRemainsAvailableAfterTheParentOutboxRowIsPruned() throws {
        let model = fixtureModel()
        model.demoMode = false
        defer { model.demoMode = true }
        model.sendMessage("Synthetic persistent parent", agent: "codex", roomId: "fixture-room")
        let parent = try XCTUnwrap(model.deliveries.first)
        model.deliveries = []
        XCTAssertEqual(model.pendingTaskOrigin(sessionId: try XCTUnwrap(parent.sessionId),
            agent: "codex", room: "fixture-room"), parent.id)
    }

    func testUnrelatedNativeCatalogDoesNotReleaseATemporaryChatID() throws {
        let model = fixtureModel()
        model.sendMessage("Synthetic pending parent", agent: "codex", roomId: "fixture-room")
        let stub = try XCTUnwrap(model.deliveries.first?.sessionId)
        let native = SessionInfo(sessionId: "unrelated-native", agent: "codex", state: "idle",
            startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        model.applySessionsStatus(.init(machine: "Fixture", sessions: [native], tokensRecent: 0,
            tokenWindowHours: 24, generatedAt: Date().timeIntervalSince1970 * 1_000),
            sourceNamespace: "fixture-room")
        XCTAssertTrue(model.localOnlySessionIds.contains(stub),
                      "A catalog refresh must never turn a temporary ID into a native delivery route.")
        model.sendMessage("Synthetic second message", agent: "codex", sessionId: stub)
        XCTAssertNotNil(model.deliveries.first { $0.text == "Synthetic second message" }?.continuationOriginId)
    }

    func testCatalogRestoresTheExactChatWhenThePhoneMissedItsCreationEvent() throws {
        let model = fixtureModel()
        model.demoMode = false
        defer { model.demoMode = true }
        model.sendMessage("Synthetic offline parent", agent: "grok", roomId: "fixture-room")
        let parent = try XCTUnwrap(model.deliveries.first)
        let stub = try XCTUnwrap(parent.sessionId)
        model.deliveries = []
        var native = SessionInfo(sessionId: "recovered-native-chat", agent: "grok", title: "Recovered synthetic chat",
            state: "idle", startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        native.creationOrigins = [.init(originId: parent.id,
            controllerPublicKey: try XCTUnwrap(model.connectionRegistry.connections.first?.pairing.myPublicKey))]
        let restored = try JSONDecoder().decode(SessionInfo.self, from: JSONEncoder().encode(native))
        model.applySessionsStatus(.init(machine: "Fixture", sessions: [restored], tokensRecent: 0,
            tokenWindowHours: 24, generatedAt: Date().timeIntervalSince1970 * 1_000),
            sourceNamespace: "fixture-room")
        XCTAssertEqual(model.resolvedSessionId(stub), native.sessionId)
        XCTAssertFalse(model.localOnlySessionIds.contains(stub))
        XCTAssertFalse(model.sessions.contains { $0.sessionId == stub })
        XCTAssertTrue(model.sessions.contains { $0.sessionId == native.sessionId })
    }

    func testCatalogLinksFromAnotherControllerOrProviderCannotAdoptThePendingChat() throws {
        let model = fixtureModel()
        model.sendMessage("Synthetic scoped parent", agent: "codex", roomId: "fixture-room")
        let parent = try XCTUnwrap(model.deliveries.first)
        let stub = try XCTUnwrap(parent.sessionId)
        let ownKey = try XCTUnwrap(model.connectionRegistry.connections.first?.pairing.myPublicKey)
        var native = SessionInfo(sessionId: "foreign-native-chat", agent: "codex", title: "Synthetic foreign chat",
            state: "idle", startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        native.creationOrigins = [.init(originId: parent.id, controllerPublicKey: "another-controller")]
        model.recoverPendingTaskOrigins(from: [native], room: "fixture-room")
        XCTAssertEqual(model.resolvedSessionId(stub), stub)
        native.creationOrigins = [.init(originId: parent.id, controllerPublicKey: ownKey)]
        var wrongProvider = native
        wrongProvider = SessionInfo(sessionId: native.sessionId, agent: "grok", title: native.title,
            state: "idle", startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        wrongProvider.creationOrigins = native.creationOrigins
        model.recoverPendingTaskOrigins(from: [wrongProvider], room: "fixture-room")
        model.recoverPendingTaskOrigins(from: [native], room: "other-room")
        XCTAssertEqual(model.resolvedSessionId(stub), stub)
        var duplicate = native
        duplicate = SessionInfo(sessionId: "another-native-chat", agent: "codex", title: native.title,
            state: "idle", startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        duplicate.creationOrigins = native.creationOrigins
        model.recoverPendingTaskOrigins(from: [native, duplicate], room: "fixture-room")
        XCTAssertEqual(model.resolvedSessionId(stub), stub, "Ambiguous links fail closed.")
        model.recoverPendingTaskOrigins(from: [native], room: "fixture-room")
        XCTAssertEqual(model.resolvedSessionId(stub), native.sessionId)
    }
}
