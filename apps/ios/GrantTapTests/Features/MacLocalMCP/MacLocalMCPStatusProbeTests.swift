#if targetEnvironment(macCatalyst)
import XCTest
@testable import GrantTap

@MainActor
final class MacLocalMCPStatusProbeTests: XCTestCase {
    func testStatusProbeFindsRunningMCPWithoutReadingWorkspace() async {
        let reader = MacLocalMCPModel()
        let running = MacLocalMCPStatus(schema: "granttap.desktop-status.v1", ok: true,
            service: "granttap-mcp", computer: "Test Mac", endpointId: nil,
            accountLinkSaved: true, version: "0.8.41", paired: true,
            relayStatus: "online", phoneReachability: nil,
            desktopEngineSocket: "/tmp/test-granttap.sock", providers: nil)

        await reader.probeStatus { running }

        XCTAssertTrue(reader.hasCheckedLocalMCP)
        XCTAssertEqual(reader.status?.computer, "Test Mac")
        XCTAssertFalse(reader.isReady, "A status probe must not unlock workspace control")
    }

    func testFailedProbeDoesNotClaimMCPIsAbsent() async {
        let reader = MacLocalMCPModel()

        await reader.probeStatus { throw MacLocalMCPError.unavailable }

        XCTAssertTrue(reader.hasCheckedLocalMCP)
        XCTAssertNil(reader.status)
        XCTAssertFalse(reader.isReady)
    }
}
#endif
