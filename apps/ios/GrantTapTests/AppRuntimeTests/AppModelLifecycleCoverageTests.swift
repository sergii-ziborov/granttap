import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testDebugStartupChoosesSideEffectFreeDemoAndForgetClearsLocalState() {
        setenv("GRANTTAP_DEMO", "1", 1)
        defer { unsetenv("GRANTTAP_DEMO") }
        let model = AppModel()
        model.start()
        XCTAssertTrue(model.demoMode)
        XCTAssertFalse(model.sessions.isEmpty)

        model.connectionRegistry = .empty
        model.forgetPairing()
        XCTAssertTrue(model.connectionRegistry.connections.isEmpty)
        XCTAssertNil(model.pairing)
    }

    @MainActor
    func testConnectionChangePublishesUpAndDebouncedDownStates() async {
        let model = AppModel()
        model.connectionRegistry = testConnectionRegistry()
        let client = RelayClient(pairing: testPairing())
        model.relay = client
        model.refreshAfterConnect = true
        model.applyConnectionChange(true, client: client)
        XCTAssertTrue(model.connected)
        XCTAssertFalse(model.refreshAfterConnect)

        model.relay = nil
        model.applyConnectionChange(
            false, client: client, disconnectDelayNanoseconds: 1_000_000
        )
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertFalse(model.connected)
    }

    @MainActor
    func testCancelledDisconnectGraceLeavesConnectedStateUntouched() async {
        let model = AppModel()
        let client = RelayClient(pairing: testPairing())
        model.connected = true
        model.applyConnectionChange(
            false, client: client, disconnectDelayNanoseconds: 20_000_000
        )
        model.applyConnectionChange(
            false, client: client, disconnectDelayNanoseconds: 1_000_000
        )
        model.connectedDebounceTask?.cancel()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(model.connected)
    }

    @MainActor
    func testRealStartupLoadsEmptyRegistryAndPurgesStaleDemoCatalog() {
        let stored = PairedConnectionStore.load()
        PairedConnectionStore.removeAll()
        defer {
            PairedConnectionStore.removeAll()
            _ = PairedConnectionStore.save(stored)
        }
        unsetenv("GRANTTAP_DEMO")
        let model = AppModel()
        model.sessions = [SessionInfo(
            sessionId: AppModelDemoFixtures.codexSessionId, agent: "codex",
            title: "Demo", state: "idle", startedAt: 1, lastActivityAt: 1,
            tokensSession: 0, tokensLastTurn: 0
        )]
        model.start()
        XCTAssertFalse(model.demoMode)
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertTrue(model.connectionRegistry.connections.isEmpty)
    }
}
