import XCTest
@testable import GrantTap

/// A connector list is only useful if a broken row offers the fix next to it.
/// The detail screen showed status and load but no action, so a computer that
/// had dropped could be seen and not repaired.
final class ConnectionActionTests: XCTestCase {
    func testABrokenLinkOffersItsRepairRightThere() {
        for phase in [ConnectionPhase.phoneOffline, .macOffline] {
            XCTAssertTrue(
                ConnectionSnapshot.needsAttention(phase),
                "\(phase) is exactly when the user came looking for a button"
            )
        }
    }

    func testAHealthyLinkDoesNotShoutForAction() {
        XCTAssertFalse(ConnectionSnapshot.needsAttention(.live))
        XCTAssertFalse(ConnectionSnapshot.needsAttention(.demo))
    }

    func testAnUnpairedComputerAsksToPairRatherThanReconnect() {
        XCTAssertTrue(ConnectionSnapshot.needsAttention(.needRepair))
        XCTAssertEqual(
            ConnectionSnapshot(phase: .needRepair, linked: true, deviceName: nil,
                               machineName: nil, roomShort: nil, catalogAgeSeconds: nil)
                .primaryActionTitle,
            "Scan QR / Pair",
            "reconnecting cannot fix a link that was never valid"
        )
    }

    func testTheRepairIsNamedForWhatItDoes() {
        for phase in [ConnectionPhase.phoneOffline, .macOffline] {
            XCTAssertEqual(
                ConnectionSnapshot(phase: phase, linked: true, deviceName: nil,
                                   machineName: nil, roomShort: nil, catalogAgeSeconds: nil)
                    .primaryActionTitle,
                "Reconnect"
            )
        }
    }
}
