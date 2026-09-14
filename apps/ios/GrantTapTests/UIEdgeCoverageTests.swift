import SwiftUI
import UIKit
import XCTest
@testable import GrantTap

@MainActor
final class UIEdgeCoverageTests: XCTestCase {
    func testNeedsYouNeverAppearsAgainInAtRisk() {
        let now = Date().timeIntervalSince1970 * 1_000
        let session = edgeSession("needs-you", at: now - 3 * 24 * 60 * 60 * 1_000)
        let model = AppModel()
        model.sessions = [session]
        model.pending = [ApprovalRequest(
            type: "approval.request", requestId: "approval", agent: "codex",
            kind: "permission", tool: "shell", title: "Allow tests?",
            command: "npm test", cwd: "/repo", sessionId: session.sessionId,
            risk: .medium, danger: .caution, createdAt: now
        )]
        let content = ContentView(modelOverride: model)

        XCTAssertEqual(content.currentTaskItems.flatMap(\.sessionIds), ["needs-you"])
        XCTAssertEqual(content.activeTaskItems.first.map(content.health), .needsYou)
        XCTAssertTrue(content.atRiskTasks.isEmpty)
    }

    func testHideRemovesTaskFromActiveUntilItIsRestored() {
        let session = edgeSession("hide-restore", at: Date().timeIntervalSince1970 * 1_000)
        let model = AppModel()
        model.sessions = [session]
        let content = ContentView(selectedTab: .tasks, modelOverride: model)

        XCTAssertEqual(content.filteredTaskItems.flatMap(\.sessionIds), [session.sessionId])
        model.setSessionArchived(session.sessionId, true)
        XCTAssertTrue(content.filteredTaskItems.isEmpty)
        XCTAssertFalse(content.atRiskTasks.contains { $0.sessionIds.contains(session.sessionId) })
        XCTAssertFalse(content.activeNowTasks.contains { $0.sessionIds.contains(session.sessionId) })
        XCTAssertFalse(content.recentTasks.contains { $0.sessionIds.contains(session.sessionId) })

        model.setSessionArchived(session.sessionId, false)
        XCTAssertEqual(content.filteredTaskItems.flatMap(\.sessionIds), [session.sessionId])
    }

    func testNowKeepsOpenWorkRegardlessOfAgeAndRecentUsesTwentyFourHours() {
        let now = Date().timeIntervalSince1970 * 1_000
        let day = 24.0 * 60 * 60 * 1_000
        var open = edgeSession("open-three-days", at: now - 3 * day)
        open.state = "waiting"
        var closedTwentyHours = edgeSession("closed-20h", at: now - 20 * 60 * 60 * 1_000)
        closedTwentyHours.state = "finished"
        var closedTwentySixHours = edgeSession("closed-26h", at: now - 26 * 60 * 60 * 1_000)
        closedTwentySixHours.state = "finished"
        let model = AppModel()
        model.sessionSourceRooms = [:]
        model.sessions = [open]
        model.sessionHistory = [closedTwentyHours, closedTwentySixHours]
        let content = ContentView(modelOverride: model)

        XCTAssertEqual(content.activeNowTasks.flatMap(\.sessionIds), ["open-three-days"])
        XCTAssertEqual(content.recentTasks.flatMap(\.sessionIds), ["closed-20h"])
    }

    func testACardReportsHowLongAgoTheTaskWasActive() {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        model.sessions = [edgeSession("aging", at: now - 3 * 60 * 60 * 1_000)]
        let item = try? XCTUnwrap(ContentView(modelOverride: model).activeTaskItems.first)
        XCTAssertEqual(item?.idleSeconds(nowMs: now), 3 * 60 * 60)
        XCTAssertEqual(ConnectionLoadFormat.age(seconds: item?.idleSeconds(nowMs: now)), "3h ago")
        XCTAssertEqual(ConnectionLoadFormat.age(seconds: 4 * 24 * 60 * 60), "4d ago")
        if let item { assertRendered(TaskListCard(item: item)) }
    }

    func testOpenIdleAndWaitingExecutionsStayWorking() {
        let now = Date().timeIntervalSince1970 * 1_000
        var idle = edgeSession("idle-live", at: now)
        idle.state = "idle"
        var waiting = edgeSession("waiting-live", at: now - 1)
        waiting.state = "waiting"
        var finished = edgeSession("finished-history", at: now - 2)
        finished.title = "Finished native title"
        let model = AppModel()
        model.sessions = [idle, waiting]
        model.sessionHistory = [finished]
        model.demoMode = true
        let content = ContentView(modelOverride: model)

        XCTAssertEqual(
            content.activeNowTasks.flatMap(\.sessionIds),
            ["idle-live", "waiting-live"]
        )
        XCTAssertEqual(content.recentTasks.flatMap(\.sessionIds), ["finished-history"])
        XCTAssertTrue(content.recentTasks.allSatisfy { $0.state == "finished" })
        XCTAssertEqual(
            content.filteredTaskItems.flatMap(\.sessionIds),
            ["idle-live", "waiting-live"]
        )
        let history = ContentView(
            selectedTab: .tasks, showArchivedSessions: true, modelOverride: model
        )
        XCTAssertEqual(
            history.filteredTaskItems.flatMap(\.sessionIds),
            ["finished-history"]
        )
    }

    func testStaleWorkingStateWithoutOpenExecutionIsNotWorking() {
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        model.meshSnapshots = ["project": staleWorkingSnapshot(at: now)]
        let content = ContentView(modelOverride: model)

        XCTAssertTrue(content.activeNowTasks.isEmpty)
        XCTAssertTrue(content.currentTaskItems.isEmpty)
    }

    func testContentSessionsCoversConnectionHintsFilteringAndOpenState() {
        let session = edgeSession("needle", at: Date().timeIntervalSince1970 * 1_000)
        let model = AppModel()
        model.sessions = [session]
        model.demoMode = true
        let tasks = ContentView(
            selectedTab: .tasks, sessionSearch: "NEEDLE",
            modelOverride: model
        )
        XCTAssertEqual(tasks.filteredTaskItems.flatMap(\.sessionIds), ["needle"])
        XCTAssertEqual(tasks.emptySessionsHint, "Start a new task, or pull to refresh.")
        tasks.open(session)
        tasks.prepareNewTask()

        let empty = AppModel()
        empty.connectionRegistry = .empty
        XCTAssertTrue(ContentView(modelOverride: empty).emptySessionsHint.contains("Connect"))
        empty.connectionRegistry = ConnectionRegistryLogic.upsert(
            .empty, pairing: edgePairing(), prefer: true
        )
        empty.roomRuntime["edge-room"] = AppModel.RoomRuntime(socketUp: false)
        XCTAssertTrue(ContentView(modelOverride: empty).emptySessionsHint.contains("offline"))
        let now = Date().timeIntervalSince1970 * 1_000
        empty.roomRuntime["edge-room"] = AppModel.RoomRuntime(
            socketUp: true, socketUpSince: now - 200_000
        )
        XCTAssertTrue(ContentView(modelOverride: empty).emptySessionsHint.contains("repair"))
        empty.roomRuntime["edge-room"] = AppModel.RoomRuntime(
            socketUp: true, socketUpSince: now
        )
        XCTAssertTrue(ContentView(modelOverride: empty).emptySessionsHint.contains("offline"))

        assertRendered(tasks.environmentObject(model))
        assertRendered(ContentView(
            selectedTab: .tasks, showArchivedSessions: true, modelOverride: empty
        ).environmentObject(empty))
        assertRendered(ContentView(modelOverride: empty).environmentObject(empty))
    }

    func testContentViewPresentsSecondarySheetsAndParsesPairingURLs() {
        let model = AppModel()
        model.demoMode = true
        for view in [
            ContentView(showPairing: true, modelOverride: model),
            ContentView(showSettings: true, modelOverride: model),
            ContentView(showConnectionDetail: true, modelOverride: model),
        ] {
            assertRendered(view.environmentObject(model))
        }

        let key = Data(repeating: 7, count: 32).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let secure = URL(string: "granttap://pair-v2?v=2&u=relay.granttap.app&m=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa&k=\(key)")!
        ContentView(
            modelOverride: model,
            securePairingFetcher: { _ in .failure(.unreachable) }
        ).handlePairingURL(secure)
        ContentView(modelOverride: model).handlePairingURL(URL(string: "granttap://invalid")!)
    }

    func testMcpIdentityMetadataAndBadgeVariantsRender() {
        XCTAssertEqual(MCPIdentity(name: " granttap ").displayName, "GrantTap")
        XCTAssertEqual(MCPIdentity(name: "github").displayName, "GitHub")
        XCTAssertEqual(MCPIdentity(name: "my-api-tool").displayName, "MY API Tool")
        XCTAssertEqual(MCPIdentity.shortToolName("mcp__github__search_issues"), "search_issues")
        XCTAssertEqual(MCPIdentity.shortToolName("plain"), "plain")
        let icons = [
            McpIconInfo(src: "https://example.com/light.png", mimeType: "image/png",
                        sizes: nil, theme: "light", sourceOrigin: nil),
            McpIconInfo(src: "https://example.com/dark.png", mimeType: "image/png",
                        sizes: nil, theme: "dark", sourceOrigin: nil),
        ]
        let server = McpServerInfo(
            name: "github", configuredEnabled: true, allowed: true,
            title: "GitHub MCP", icons: icons, metadataSource: "mcp"
        )
        XCTAssertEqual(server.displayTitle, "GitHub MCP")
        XCTAssertEqual(server.preferredIcon(for: .dark)?.theme, "dark")
        var fallback = server
        fallback.metadataSource = nil
        XCTAssertEqual(fallback.displayTitle, "GitHub")
        XCTAssertNil(fallback.preferredIcon(for: .light))
        assertRendered(HStack {
            MCPBadge(name: "github", size: 44, showsName: true, server: server)
            MCPBadge(name: "my-api", size: 28, showsName: true)
        })
    }

    func testSecurityLockRendersSetupConfirmEntryProgressAndError() {
        let enabledKey = "granttap.security.device-owner-auth"
        let oldEnabled = UserDefaults.standard.object(forKey: enabledKey)
        defer {
            if let oldEnabled { UserDefaults.standard.set(oldEnabled, forKey: enabledKey) }
            else { UserDefaults.standard.removeObject(forKey: enabledKey) }
            AppPinStore.clear()
        }
        AppPinStore.clear()
        UserDefaults.standard.set(false, forKey: enabledKey)
        let gate = SecurityGate(authenticator: EdgeAuthenticator(result: .success))
        gate.setEnabled(true)
        assertRendered(SecurityLockView(security: gate, pendingCount: 1))
        XCTAssertTrue(gate.completePinSetupDigit("123456"))
        assertRendered(SecurityLockView(security: gate, pendingCount: 2))

        XCTAssertTrue(AppPinStore.save("123456"))
        UserDefaults.standard.set(true, forKey: enabledKey)
        let locked = SecurityGate(authenticator: EdgeAuthenticator(result: .failure("No ID")))
        locked.beginPinEntry()
        assertRendered(SecurityLockView(security: locked, pendingCount: 0))
        locked.cancelPinEntry()
        locked.errorText = "Authentication failed"
        assertRendered(SecurityLockView(security: locked, pendingCount: 3))

        let waiting = SecurityGate(authenticator: EdgeAuthenticator(result: nil))
        waiting.setEnabled(true)
        assertRendered(SecurityLockView(security: waiting, pendingCount: 0))
    }

    private func edgeSession(_ id: String, at: Double) -> SessionInfo {
        SessionInfo(
            sessionId: id, agent: "codex", title: "Needle task", cwd: "/repo",
            state: "working", startedAt: at - 1, lastActivityAt: at,
            tokensSession: 0, tokensLastTurn: 0
        )
    }

    private func edgePairing() -> Pairing {
        Pairing(
            relayUrl: "ws://127.0.0.1:1", room: "edge-room", role: "phone",
            deviceName: "Edge Mac", senderId: "edge", myPublicKey: "public",
            mySecretKey: "secret", peerPublicKey: "peer"
        )
    }

    private func staleWorkingSnapshot(at now: Double) -> ProjectMeshSnapshot {
        ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(
                projectId: "project", name: "GrantTap", repositoryRoot: "/repo",
                canonicalRepositoryId: "github.com/example/granttap",
                baseRemote: nil, createdAt: now
            ),
            tasks: [.init(
                taskId: "stale", projectId: "project", title: "Stale task", goal: "",
                state: "working", ownerSessionId: nil, createdAt: now, updatedAt: now
            )],
            executions: [], claims: [], dependencies: [], events: [], generatedAt: now
        )
    }

    private func assertRendered<V: View>(_ view: V) {
        let frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: frame)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = frame
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        XCTAssertNotNil(controller.view.window)
        window.isHidden = true
    }
}

@MainActor
private final class EdgeAuthenticator: DeviceOwnerAuthenticating {
    let biometryName = "Edge ID"
    let result: DeviceOwnerAuthResult?
    init(result: DeviceOwnerAuthResult?) { self.result = result }
    func authenticate(
        reason: String,
        completion: @escaping @MainActor (DeviceOwnerAuthResult) -> Void
    ) {
        if let result { completion(result) }
    }
}
