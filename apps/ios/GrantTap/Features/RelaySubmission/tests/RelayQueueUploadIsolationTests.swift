import XCTest
import TweetNacl
@testable import GrantTap

@MainActor
final class RelayQueueUploadIsolationTests: XCTestCase {
    func testNewUploadDoesNotWaitForAnOlderReceiptRequest() async throws {
        let phone = try NaclBox.keyPair(), machine = try NaclBox.keyPair()
        let pairing = Pairing(relayUrl: "https://relay-isolation.test", room: String(repeating: "a", count: 32),
            role: "phone", deviceName: "Fixture", senderId: "fixture",
            myPublicKey: phone.publicKey.base64EncodedString(), mySecretKey: phone.secretKey.base64EncodedString(),
            peerPublicKey: machine.publicKey.base64EncodedString(), pushAuth: String(repeating: "b", count: 64))
        let model = AppModel()
        model.demoMode = true
        model.deliveries = []
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: pairing)
        let chat = SessionInfo(sessionId: "isolation-chat", agent: "codex", state: "working",
            startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        model.sessions = [chat]
        model.sessionSourceRooms = [chat.sessionId: [pairing.room]]
        XCTAssertTrue(model.queueChatMessage("Earlier queued fixture", to: chat))
        let oldID = try XCTUnwrap(model.deliveries.first?.id)
        model.deliveries[0].chatQueue?.relayManaged = true
        model.deliveries[0].relayJob = .init(jobId: oldID, token: nil, notBefore: 1,
            expiresAt: 2_000_000, createdAt: 1, uploadAttempted: true, serverState: .queued)
        let polling = expectation(description: "Earlier receipt request is waiting")
        var held: UploadIsolationURLProtocol?
        UploadIsolationURLProtocol.handle = { request in
            if request.request.httpMethod == "GET" {
                held = request
                polling.fulfill()
            } else { request.reply() }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UploadIsolationURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            held?.reply()
            UploadIsolationURLProtocol.handle = nil
            session.invalidateAndCancel()
            for row in model.deliveries { RelayTaskQueueCipherStore.remove(row.id) }
        }
        let pending = Task { await model.synchronizeRelayTaskQueues(session: session) }
        await fulfillment(of: [polling], timeout: 5)
        XCTAssertTrue(model.relayQueueSyncInProgress)
        XCTAssertTrue(model.queueChatMessage("New queued fixture", to: chat))
        let newID = try XCTUnwrap(model.deliveries.last?.id)
        model.deliveries[1].chatQueue?.relayManaged = true
        await model.uploadNewRelayTaskQueues(session: session)
        XCTAssertEqual(model.deliveries.first { $0.id == newID }?.relayJob?.serverState, .queued)
        XCTAssertTrue(model.relayQueueSyncInProgress, "The old receipt is still waiting when the upload finishes")
        held?.reply()
        held = nil
        await pending.value
    }
}

private final class UploadIsolationURLProtocol: URLProtocol {
    static var handle: ((UploadIsolationURLProtocol) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "relay-isolation.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handle?(self) }
    override func stopLoading() {}

    func reply() {
        guard let url = request.url else { return }
        let receipt: [String: Any] = ["job": ["id": url.lastPathComponent, "state": "queued",
            "notBefore": 1_000_000, "expiresAt": 2_000_000]]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: receipt))
        client?.urlProtocolDidFinishLoading(self)
    }
}
