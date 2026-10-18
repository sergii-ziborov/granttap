import XCTest
@testable import GrantTap

#if targetEnvironment(simulator)
/// Test-only setup uses the application's secure pairing persistence.
final class RelayPairingSetupTests: XCTestCase {
    @MainActor
    func testSaveDedicatedRelayPairingForDeviceVerification() async throws {
        let (data, response) = try await URLSession.shared.data(
            from: URL(string: "http://127.0.0.1:42202/pairing-json")!)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let pairing = try JSONDecoder().decode(Pairing.self, from: data)
        XCTAssertEqual(pairing.relayUrl, "ws://127.0.0.1:42201")
        XCTAssertEqual(pairing.deviceName, "Relay validation computer")
        AppRuntime.reconcileInstall()
        XCTAssertTrue(pairing.save())
        XCTAssertEqual(Pairing.load()?.room, pairing.room)
    }
}
#endif
