import XCTest
import TweetNacl
@testable import GrantTap

@MainActor
final class RelayTaskQueueRuntimeTests: XCTestCase {
    private func fixture() throws -> (AppModel, URLSession, SessionInfo) {
        let phone = try NaclBox.keyPair(), machine = try NaclBox.keyPair()
        let pairing = Pairing(relayUrl: "wss://relay.test", room: String(repeating: "a", count: 32),
            role: "phone", deviceName: "Fixture", senderId: "fixture",
            myPublicKey: phone.publicKey.base64EncodedString(), mySecretKey: phone.secretKey.base64EncodedString(),
            peerPublicKey: machine.publicKey.base64EncodedString(), pushAuth: String(repeating: "b", count: 64))
        let model = AppModel()
        model.demoMode = true
        model.deliveries = []
        model.activities = [:]
        model.localOnlySessionIds = []
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: pairing)
        model.noteMachineHeartbeat(MachineHeartbeat(machine: "Fixture", createdAt: 1,
            taskQueueImmediate: true), fromRoom: pairing.room)
        model.sessionSourceRooms = ["fixture-chat": [pairing.room]]
        let chat = SessionInfo(sessionId: "fixture-chat", agent: "codex", state: "working",
            startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        model.sessions = [chat]
        XCTAssertTrue(model.queueChatMessage("Synthetic queued task", to: chat,
            attachments: [UserAttachment(name: "photo.png", mimeType: "image/png", data: "AQID")]))
        model.deliveries[0].chatQueue?.relayManaged = true
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayQueueURLProtocol.self]
        let session = URLSession(configuration: config)
        addTeardownBlock {
            session.invalidateAndCancel()
            for row in model.deliveries { RelayTaskQueueCipherStore.remove(row.id) }
        }
        return (model, session, chat)
    }

    func testUploadRetryKeepsTheSameCiphertextAndDoesNotNeedTheComputerOnline() async throws {
        let (model, session, chat) = try fixture()
        let id = try XCTUnwrap(model.deliveries.first?.id)
        var bodies: [Data] = []
        RelayQueueURLProtocol.handle = { request in
            if let body = request.httpBody { bodies.append(body) }
            return (bodies.count == 1 ? 503 : 201, Self.receipt(id, state: "queued"))
        }
        await model.synchronizeRelayTaskQueues(session: session)
        XCTAssertNil(model.deliveries[0].relayJob?.serverState)
        XCTAssertNotNil(model.deliveries[0].error)
        await model.synchronizeRelayTaskQueues(session: session)
        XCTAssertEqual(bodies.count, 2)
        XCTAssertTrue(bodies[0] == bodies[1])
        XCTAssertEqual(model.deliveries[0].relayJob?.serverState, .queued)
        XCTAssertNil(model.deliveries[0].error)
        XCTAssertEqual(model.deliveries[0].attachments.first?.data, "AQID")
        XCTAssertFalse(model.connected)
        XCTAssertTrue(ChatMessageQueuePolicy.ready(model.deliveries, observed: [chat]).isEmpty)
    }

    func testSendNowResolvesAnUnconfirmedUploadBeforeCancellingItsImmutableOperation() async throws {
        let (model, session, _) = try fixture()
        let id = try XCTUnwrap(model.deliveries.first?.id)
        var bodies: [Data] = []
        RelayQueueURLProtocol.handle = { request in
            if let body = request.httpBody { bodies.append(body) }
            if request.httpMethod == "DELETE" { return (200, Self.receipt(id, state: "cancelled")) }
            return (bodies.count == 1 ? 503 : 201, Self.receipt(id, state: "queued"))
        }
        await model.synchronizeRelayTaskQueues(session: session)
        model.sendChatQueuedMessageNow(id)
        XCTAssertEqual(model.deliveries[0].chatQueue?.cancelRequested, true)
        await model.synchronizeRelayTaskQueues(session: session)
        XCTAssertNotEqual(model.deliveries[0].id, id)
        XCTAssertEqual(bodies.count, 2)
        XCTAssertEqual(bodies.first, bodies.last)
        XCTAssertNil(model.deliveries[0].relayJob)
        XCTAssertEqual(model.deliveries[0].chatQueue?.sendImmediately, true)
    }

    func testRetryCancelsTheOldOperationBeforeCreatingASeparateAttemptWithTheSameImage() async throws {
        let (model, session, _) = try fixture()
        let original = try XCTUnwrap(model.deliveries.first?.id)
        RelayQueueURLProtocol.handle = { _ in (201, Self.receipt(original, state: "queued")) }
        await model.synchronizeRelayTaskQueues(session: session)
        model.applyRelayTaskQueueReceipt(try JSONDecoder().decode(RelayTaskJobReceipt.self,
            from: Self.receipt(original, state: "failed", wrapped: false)), to: original)
        XCTAssertEqual(model.deliveries[0].state, .failed)
        var methods: [String] = []
        RelayQueueURLProtocol.handle = { request in
            methods.append(request.httpMethod ?? "")
            return (200, Self.receipt(original, state: request.httpMethod == "DELETE" ? "cancelled" : "failed"))
        }
        model.sendChatQueuedMessageNow(original)
        XCTAssertEqual(model.deliveries.first?.id, original, "A request to cancel is not cancellation evidence.")
        await model.synchronizeRelayTaskQueues(session: session)
        XCTAssertEqual(methods, ["GET", "DELETE"])
        XCTAssertNotEqual(model.deliveries.first?.id, original)
        XCTAssertEqual(model.deliveries.first?.attachments.first?.data, "AQID")
        XCTAssertEqual(model.deliveries.first?.chatQueue?.sendImmediately, true)
        let restored = try JSONDecoder().decode(OutgoingDelivery.self,
            from: JSONEncoder().encode(try XCTUnwrap(model.deliveries.first)))
        XCTAssertEqual(restored.chatQueue?.sendImmediately, true)
        XCTAssertNil(model.deliveries.first?.relayJob)
    }

    func testSendNowCancelsAConfirmedWaitingJobBeforeReplacingIt() async throws {
        let (model, session, _) = try fixture()
        let original = try XCTUnwrap(model.deliveries.first?.id)
        RelayQueueURLProtocol.handle = { _ in (201, Self.receipt(original, state: "queued")) }
        await model.synchronizeRelayTaskQueues(session: session)
        model.sendChatQueuedMessageNow(original)
        XCTAssertEqual(model.deliveries.first?.chatQueue?.cancelRequested, true)
        XCTAssertEqual(model.deliveries.first?.id, original)
        var methods: [String] = []
        RelayQueueURLProtocol.handle = { request in
            methods.append(request.httpMethod ?? "")
            return (200, Self.receipt(original, state: request.httpMethod == "DELETE" ? "cancelled" : "queued"))
        }
        await model.synchronizeRelayTaskQueues(session: session)
        XCTAssertEqual(methods, ["GET", "DELETE"])
        XCTAssertNotEqual(model.deliveries.first?.id, original)
        XCTAssertEqual(model.deliveries.first?.attachments.first?.data, "AQID")
    }

    func testSendNowCannotReplayAnOperationAcceptedDuringCancellation() async throws {
        let (model, session, _) = try fixture()
        let original = try XCTUnwrap(model.deliveries.first?.id)
        RelayQueueURLProtocol.handle = { _ in (201, Self.receipt(original, state: "queued")) }
        await model.synchronizeRelayTaskQueues(session: session)
        model.sendChatQueuedMessageNow(original)
        var methods: [String] = []
        RelayQueueURLProtocol.handle = { request in
            methods.append(request.httpMethod ?? "")
            return (200, Self.receipt(original, state: "accepted"))
        }
        await model.synchronizeRelayTaskQueues(session: session)
        XCTAssertEqual(methods, ["GET"])
        XCTAssertEqual(model.deliveries.count, 1)
        XCTAssertEqual(model.deliveries.first?.id, original)
        XCTAssertEqual(model.deliveries.first?.relayJob?.serverState, .accepted)
        XCTAssertNotNil(model.deliveries.first?.error)
    }

    func testUnsentCancellationDoesNotUploadAnOperationJustToDeleteIt() async throws {
        let (model, session, _) = try fixture()
        let id = try XCTUnwrap(model.deliveries.first?.id)
        var networkCalls = 0
        RelayQueueURLProtocol.handle = { _ in networkCalls += 1; return (500, Data()) }
        XCTAssertTrue(model.cancelChatQueuedMessage(id))
        await model.synchronizeRelayTaskQueues(session: session)
        XCTAssertEqual(networkCalls, 0)
        XCTAssertTrue(model.deliveries.isEmpty)
    }

    func testSendNowKeepsTheExistingJobWhenTheComputerNeedsAnUpdate() async throws {
        let (model, session, _) = try fixture()
        let id = try XCTUnwrap(model.deliveries.first?.id)
        RelayQueueURLProtocol.handle = { _ in (201, Self.receipt(id, state: "queued")) }
        await model.synchronizeRelayTaskQueues(session: session)
        model.connectionRegistry.connections[0].taskQueueImmediate = nil
        model.sendChatQueuedMessageNow(id)
        XCTAssertEqual(model.deliveries.first?.id, id)
        XCTAssertNotEqual(model.deliveries.first?.chatQueue?.cancelRequested, true)
        XCTAssertEqual(model.deliveries.first?.relayJob?.serverState, .queued)
        XCTAssertNotNil(model.deliveries.first?.error)
    }

    func testARejectedRelayJobCannotBeEvictedWhileItStillBlocksQueuedFollowUps() throws {
        let (model, _, _) = try fixture()
        var rejected = model.deliveries[0]
        rejected.state = .failed
        let next = OutgoingDelivery(id: UUID().uuidString, text: "Another synthetic task", agent: "codex",
            cwd: nil, sessionId: "fixture-chat", requestId: nil, attachments: [], preferredMcp: nil, skill: nil,
            createdAt: 1, updatedAt: 1, attempts: 0, state: .queued, error: nil, nextRetryAt: nil)
        let admission = DeliveryPersistence.admit(next, into: [rejected], maxActiveCount: 1)
        XCTAssertFalse(admission.shouldSend)
        XCTAssertTrue(admission.deliveries.contains(where: { $0.id == rejected.id && !$0.attachments.isEmpty }))
    }

    private nonisolated static func receipt(_ id: String, state: String, wrapped: Bool = true) -> Data {
        let value: [String: Any] = ["id": id, "state": state, "notBefore": 1_000_000,
            "expiresAt": 2_000_000, "resultCode": state == "failed" ? "confirmation_required" : ""]
        if wrapped { return try! JSONSerialization.data(withJSONObject: ["job": value]) }
        return try! JSONSerialization.data(withJSONObject: value)
    }
}

private final class RelayQueueURLProtocol: URLProtocol {
    static var handle: ((URLRequest) -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "relay.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open()
            var data = Data(), bytes = [UInt8](repeating: 0, count: 4_096)
            while true {
                let count = stream.read(&bytes, maxLength: 4_096)
                if count <= 0 { break }
                data.append(contentsOf: bytes.prefix(count))
            }
            stream.close()
            captured.httpBody = data
        }
        let (status, data) = Self.handle?(captured) ?? (500, Data())
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
            httpVersion: nil, headerFields: ["content-type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
