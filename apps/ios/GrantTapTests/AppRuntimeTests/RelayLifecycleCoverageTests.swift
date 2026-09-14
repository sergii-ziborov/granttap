import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testRelayOpenAndCloseDelegatesOnlyMutateCurrentSocket() throws {
        var pairing = testPairing()
        pairing.pushAuth = "fixture-auth"
        let client = RelayClient(pairing: pairing)
        let session = URLSession(configuration: .ephemeral)
        let socket = session.webSocketTask(with: URL(string: "ws://127.0.0.1:1/ws")!)
        client.wantsConnection = true
        client.task = socket
        client.recoverPeerOnNextHello = true
        var edges: [Bool] = []
        client.onConnectionChange = { edges.append($0) }

        client.urlSession(session, webSocketTask: socket, didOpenWithProtocol: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        XCTAssertTrue(edges.contains(true))
        XCTAssertFalse(client.recoverPeerOnNextHello)

        client.urlSession(
            session, webSocketTask: socket,
            didCloseWith: .goingAway, reason: nil
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        XCTAssertNil(client.task)
        XCTAssertTrue(edges.contains(false))
        client.disconnect()
        session.invalidateAndCancel()
    }

    @MainActor
    func testRelayDelegatesIgnoreStaleSocketAndPushAuthConnects() {
        var pairing = testPairing()
        pairing.pushAuth = "fixture-auth"
        let client = RelayClient(pairing: pairing)
        let session = URLSession(configuration: .ephemeral)
        let current = session.webSocketTask(with: URL(string: "ws://127.0.0.1:1/current")!)
        let stale = session.webSocketTask(with: URL(string: "ws://127.0.0.1:1/stale")!)
        client.task = current
        client.urlSession(session, webSocketTask: stale, didOpenWithProtocol: nil)
        client.urlSession(session, webSocketTask: stale, didCloseWith: .goingAway, reason: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        XCTAssertTrue(client.task === current)
        client.disconnect()

        let connecting = RelayClient(pairing: pairing)
        connecting.connect()
        XCTAssertNotNil(connecting.task)
        connecting.disconnect()
        session.invalidateAndCancel()
    }
}
