import XCTest
@testable import GrantTap

@MainActor
final class PushAndLogTests: XCTestCase {
    func testRegisterAgainAlwaysRequestsFreshSystemToken() {
        let manager = PushRegistrationManager()
        var requests = 0

        manager.registerAgain { requests += 1 }

        XCTAssertEqual(requests, 1)
        XCTAssertEqual(manager.state, .registering)
    }

    func testLogFilterSeparatesFailuresWithoutHidingSearch() {
        let ok = AuditEvent(id: "ok", createdAt: 1, action: "delivery",
                            detail: "Message delivered", outcome: "ok")
        let failed = AuditEvent(id: "bad", createdAt: 2, action: "push",
                                detail: "Relay registration failed", outcome: "failed")

        XCTAssertEqual(AuditLogFilter.all.apply([ok, failed], search: "").count, 2)
        XCTAssertEqual(AuditLogFilter.errors.apply([ok, failed], search: "").map(\.id), ["bad"])
        XCTAssertEqual(AuditLogFilter.all.apply([ok, failed], search: "delivered").map(\.id), ["ok"])
    }

    func testPushRegistrationCoversNoTokenNoLinkAndMissingAuthStates() async {
        let model = AppModel()
        let transport = StubPushTransport()
        let manager = PushRegistrationManager(model: model, transport: transport)
        manager.registerCurrentPairing()
        XCTAssertEqual(manager.state, .registering)

        manager.didRegister(deviceToken: Data([0x01, 0xAF]))
        XCTAssertEqual(manager.state, .idle)
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            .empty, pairing: pushPairing(room: "missing-auth", auth: nil)
        )
        manager.pairingDidChange()
        await waitForPushState(manager) { state in
            if case .unavailable = state { return true }
            return false
        }
        XCTAssertEqual(
            manager.state,
            .unavailable(L("Pair again to enable background delivery."))
        )
    }

    func testPushRegistrationCoversSuccessDisabledAndFailureResponses() async {
        let successModel = AppModel()
        successModel.connectionRegistry = ConnectionRegistryLogic.upsert(
            .empty, pairing: pushPairing(room: "success", auth: "auth")
        )
        let successTransport = StubPushTransport(results: [
            .success(response(status: 200, body: ["enabled": true, "devices": 3])),
        ])
        let success = PushRegistrationManager(model: successModel, transport: successTransport)
        success.didRegister(deviceToken: Data([1, 2]))
        await waitForPushState(success) { $0 == .active(3) }
        XCTAssertEqual(successTransport.requests.first?.httpMethod, "PUT")
        XCTAssertEqual(successTransport.requests.first?.value(forHTTPHeaderField: "Authorization"),
                       "Bearer auth")

        let disabledTransport = StubPushTransport(results: [
            .success(response(status: 200, body: ["enabled": false])),
        ])
        let disabled = PushRegistrationManager(model: successModel, transport: disabledTransport)
        disabled.didRegister(deviceToken: Data([3]))
        await waitForPushState(disabled) {
            $0 == .unavailable(L("The relay has no APNs provider key."))
        }

        let failedTransport = StubPushTransport(results: [
            .success(response(status: 503, body: [:])),
        ])
        let failed = PushRegistrationManager(model: successModel, transport: failedTransport)
        failed.didRegister(deviceToken: Data([4]))
        await waitForPushState(failed) {
            if case .failed = $0 { return true }
            return false
        }
        guard case .failed(let message) = failed.state else {
            return XCTFail("Expected HTTP failure")
        }
        XCTAssertTrue(message.contains("503"))
    }

    func testPushUnregisterEndpointEnvironmentAndFailureCallback() async {
        let model = AppModel()
        let pairing = pushPairing(room: "delete", auth: "auth", relay: "wss://relay.test/ws")
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: pairing)
        let transport = StubPushTransport(results: [
            .success(response(status: 200, body: [:])),
            .success(response(status: 200, body: [:])),
        ])
        let manager = PushRegistrationManager(model: model, transport: transport)
        manager.didRegister(deviceToken: Data([5]))
        await waitForPushState(manager) { if case .unavailable = $0 { return true }; return false }
        manager.unregister(pairing)
        await waitUntil { transport.requests.contains { $0.httpMethod == "DELETE" } }
        XCTAssertEqual(manager.endpoint(pairing, path: "/push/register")?.scheme, "https")
        XCTAssertEqual(manager.endpoint(
            pushPairing(room: "http", auth: "a", relay: "ws://relay.test/ws"),
            path: "/push/register"
        )?.scheme, "http")
        XCTAssertNil(manager.endpoint(
            pushPairing(room: "bad", auth: "a", relay: "::bad::"), path: "/push/register"
        ))
        XCTAssertEqual(PushRegistrationManager.resolveApnsEnvironment(" PROD ", fallback: "x"),
                       "production")
        XCTAssertEqual(PushRegistrationManager.resolveApnsEnvironment("dev", fallback: "x"),
                       "sandbox")
        XCTAssertEqual(PushRegistrationManager.resolveApnsEnvironment("other", fallback: "x"), "x")
        XCTAssertFalse(PushRegistrationManager.apnsEnvironment.isEmpty)

        manager.didFail(StubPushError.failed)
        guard case .failed = manager.state else { return XCTFail("Expected callback failure") }
    }

    private func pushPairing(
        room: String, auth: String?, relay: String = "https://relay.test/ws"
    ) -> Pairing {
        Pairing(
            relayUrl: relay, room: room, role: "phone", deviceName: room,
            senderId: "push", myPublicKey: "public", mySecretKey: "secret",
            peerPublicKey: "peer", pushAuth: auth
        )
    }

    private func response(
        status: Int, body: [String: Any]
    ) -> (Data, URLResponse) {
        let data = try! JSONSerialization.data(withJSONObject: body)
        let response = HTTPURLResponse(
            url: URL(string: "https://relay.test/push/register")!,
            statusCode: status, httpVersion: nil, headerFields: nil
        )!
        return (data, response)
    }

    private func waitForPushState(
        _ manager: PushRegistrationManager,
        _ predicate: @escaping (PushRegistrationManager.State) -> Bool
    ) async {
        await waitUntil { predicate(manager.state) }
    }

    private func waitUntil(_ predicate: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(1)
        while !predicate(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private enum StubPushError: Error { case failed }

@MainActor
private final class StubPushTransport: PushRegistrationTransport {
    typealias Result = Swift.Result<(Data, URLResponse), Error>
    var results: [Result]
    var requests: [URLRequest] = []

    init(results: [Result] = []) { self.results = results }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !results.isEmpty else { throw StubPushError.failed }
        return try results.removeFirst().get()
    }
}
