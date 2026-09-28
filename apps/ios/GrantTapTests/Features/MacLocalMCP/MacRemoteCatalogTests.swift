#if targetEnvironment(macCatalyst)
import XCTest
@testable import GrantTap

@MainActor
final class MacRemoteCatalogTests: XCTestCase {
    func testSparseReportPreservesHistoryAndCapabilitiesForExactExecution() {
        let model = model()
        var live = session("pc-live")
        live.shellAllowed = true
        let history = session("pc-history")
        model.captureMacRemoteCatalog(status([live], history: [history]), fromRoom: "test-room")
        model.captureMacRemoteCatalog(status([session("pc-live")]), fromRoom: "test-room")
        XCTAssertEqual(model.macRemoteCatalogs["test-room"]?.history, [history])
        XCTAssertEqual(model.macRemoteCatalogs["test-room"]?.sessions.first?.shellAllowed, true)
        var otherTask = session("pc-live")
        otherTask.taskId = "another-task"
        model.captureMacRemoteCatalog(status([otherTask]), fromRoom: "test-room")
        XCTAssertNil(model.macRemoteCatalogs["test-room"]?.sessions.first?.shellAllowed)
    }

    func testUnknownRoomAndDemoRowsNeverEnterCombinedCatalog() {
        let model = model()
        model.captureMacRemoteCatalog(status([session("pc-live")]), fromRoom: "removed-room")
        XCTAssertNil(model.macRemoteCatalogs["removed-room"])
        model.captureMacRemoteCatalog(status([session("granttap-codex-demo")]), fromRoom: "test-room")
        XCTAssertTrue(model.macRemoteCatalogs["test-room"]?.sessions.isEmpty == true)
    }

    private func model() -> AppModel {
        let model = AppModel()
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        let pair = Pairing(relayUrl: "wss://relay.granttap.com", room: "test-room", role: "phone",
                           deviceName: "Test PC", senderId: "test", myPublicKey: key,
                           mySecretKey: key, peerPublicKey: key)
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: pair)
        return model
    }

    private func session(_ id: String) -> SessionInfo {
        var row = SessionInfo(sessionId: id, agent: "codex", projectId: "p", taskId: "t", computerId: "pc",
                    title: "Test conversation", state: "idle", startedAt: 1, lastActivityAt: 2,
                    tokensSession: 0, tokensLastTurn: 0)
        row.shellAllowed = nil
        return row
    }

    private func status(_ sessions: [SessionInfo], history: [SessionInfo]? = nil) -> SessionsStatus {
        SessionsStatus(machine: "Test PC", sessions: sessions, history: history,
                       tokensRecent: 0, tokenWindowHours: 1, generatedAt: 2)
    }
}
#endif
