import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testScheduledReconnectDoesNotReplaceRecoveredSocket() {
        let client = RelayClient(pairing: testPairing())
        let session = URLSession(configuration: .ephemeral)
        let recovered = session.webSocketTask(with: URL(string: "ws://127.0.0.1:1/recovered")!)
        client.wantsConnection = true
        client.retryDelay = 0.02
        client.scheduleReconnect()
        client.task = recovered
        var downEdges = 0
        client.onConnectionChange = { if !$0 { downEdges += 1 } }
        RunLoop.main.run(until: Date().addingTimeInterval(0.09))
        XCTAssertTrue(client.task === recovered)
        XCTAssertEqual(downEdges, 0)
        client.disconnect()
        session.invalidateAndCancel()
    }
}
