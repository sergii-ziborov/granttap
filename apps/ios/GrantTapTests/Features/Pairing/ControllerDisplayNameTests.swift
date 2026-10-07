import XCTest
@testable import GrantTap

final class ControllerDisplayNameTests: XCTestCase {
    func testCustomNameIdentifiesThisPhoneAcrossComputerConnections() {
        let suite = "granttap-controller-name-test-\(UUID())"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        XCTAssertEqual(ControllerDisplayName.current(store: store, systemName: "iPhone"), "iPhone")
        XCTAssertTrue(ControllerDisplayName.save("  Sergii’s iPhone  ", store: store))
        XCTAssertEqual(ControllerDisplayName.current(store: store, systemName: "iPhone"),
                       "Sergii’s iPhone")
        XCTAssertFalse(ControllerDisplayName.save("bad\nname", store: store))
        XCTAssertEqual(ControllerDisplayName.current(store: store, systemName: "iPhone"),
                       "Sergii’s iPhone")
    }
}
