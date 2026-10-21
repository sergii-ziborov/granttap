import XCTest
import TweetNacl
@testable import GrantTap

@MainActor
final class RelayQueueRemoteRestoreTests: XCTestCase {
    func testEmptyOutboxRestoresFromRelayUsingOnlyGETAndSurvivesASecondRefresh() async throws {
        let phone = try NaclBox.keyPair(), machine = try NaclBox.keyPair()
        let pair = Pairing(relayUrl: "wss://relay.test", room: String(repeating: "a", count: 32),
            role: "phone", deviceName: "Fixture", senderId: "fixture", myPublicKey: phone.publicKey.base64EncodedString(),
            mySecretKey: phone.secretKey.base64EncodedString(), peerPublicKey: machine.publicKey.base64EncodedString(),
            pushAuth: String(repeating: "b", count: 64))
        let message = Payloads.message("Synthetic restored queue", messageId: "remote-restore-01", agent: "codex",
            cwd: nil, sessionId: "fixture-chat")
        let reservation = try RelayTaskQueueEncoding.prepare(message, pairing: pair, notBefore: 1000100, now: 1000000)
        let body = try JSONSerialization.jsonObject(with: reservation.uploadBody()) as! [String: Any]
        let receipt: [String: Any] = ["id": reservation.jobId, "state": "queued", "notBefore": reservation.notBefore,
                                    "expiresAt": reservation.expiresAt]
        let complete = receipt.merging(["envelope": body["envelope"]!]) { _, new in new }
        var paths: [String] = []
        RemoteQueueProtocol.reply = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
            paths.append(request.url!.path)
            return (200, try! JSONSerialization.data(withJSONObject:
                request.url!.path == "/task-jobs" ? ["jobs": [receipt]] : ["job": complete]))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RemoteQueueProtocol.self]
        let transport = URLSession(configuration: config)
        defer { transport.invalidateAndCancel(); RelayTaskQueueCipherStore.remove(reservation.jobId) }
        let saved = DeliveryPersistence.load()
        defer { DeliveryPersistence.save(saved) }
        let model = AppModel()
        model.demoMode = true
        model.deliveries = []
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: pair)
        XCTAssertFalse(model.connected)
        await model.restoreRelayTaskQueue(room: pair.room, session: transport)
        XCTAssertEqual(model.deliveries.map(\.id), [reservation.jobId])
        XCTAssertEqual(model.deliveries.first?.text, message.text)
        XCTAssertNil(model.deliveries.first?.relayJob?.envelope, "Large ciphertext stays outside rewritten metadata")
        await model.restoreRelayTaskQueue(room: pair.room, session: transport)
        XCTAssertEqual(model.deliveries.count, 1)
        XCTAssertEqual(paths, ["/task-jobs", "/task-jobs/remote-restore-01", "/task-jobs"])
        RemoteQueueProtocol.reply = { _ in (503, Data()) }
        await model.restoreRelayTaskQueue(room: pair.room, session: transport)
        XCTAssertEqual(model.deliveries.count, 1, "A failed read cannot remove relay-confirmed work")
    }
}

private final class RemoteQueueProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var reply: (URLRequest) -> (Int, Data) = { _ in (503, Data()) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.reply(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
