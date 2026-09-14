import SwiftUI
import UIKit
import XCTest
@testable import GrantTap

@MainActor
final class SettingsLifecycleCoverageTests: XCTestCase {
    private let enabledKey = "granttap.security.device-owner-auth"

    override func setUp() {
        UserDefaults.standard.set(false, forKey: enabledKey)
        UserDefaults.standard.removeObject(forKey: SecurityGate.lockDelayKey)
        AppPinStore.clear()
    }

    override func tearDown() {
        UserDefaults.standard.set(false, forKey: enabledKey)
        UserDefaults.standard.removeObject(forKey: SecurityGate.lockDelayKey)
        AppPinStore.clear()
    }

    func testApprovalBindingMapsAndWritesAllPersonalModes() {
        let model = AppModel()
        let settings = SettingsSheet(modelOverride: model)
        model.gatingEnabled = false
        XCTAssertEqual(settings.approvalBinding.wrappedValue, .defaults)
        settings.approvalBinding.wrappedValue = .every
        XCTAssertTrue(model.gatingEnabled)
        XCTAssertEqual(model.autoAcceptDefault, "ask")
        XCTAssertEqual(settings.approvalBinding.wrappedValue, .every)
        settings.approvalBinding.wrappedValue = .risky
        XCTAssertEqual(model.autoAcceptDefault, "except_push")
        XCTAssertEqual(settings.approvalBinding.wrappedValue, .risky)
        settings.approvalBinding.wrappedValue = .defaults
        XCTAssertFalse(model.gatingEnabled)
        XCTAssertEqual(Set(DefaultApprovalMode.allCases.map(\.label)).count, 3)
    }

    func testSettingsTroubleshootingAndPushStatusVariantsRender() {
        let model = AppModel()
        assertRendered(SettingsSheet(modelOverride: model).environmentObject(model))
        model.startDemo()
        assertRendered(SettingsSheet(modelOverride: model).environmentObject(model))
        model.stopDemo()

        let states: [PushRegistrationManager.State] = [
            .idle, .registering, .active(2), .unavailable("Pair again"), .failed("Offline"),
        ]
        for state in states {
            let push = PushRegistrationManager(model: model, initialState: state)
            let view = TroubleshootingView(push: push)
            assertRendered(NavigationView { view.environmentObject(model) })
            assertRendered(view.readiness("Codex", status: "Ready"))
        }
    }

    func testSecuritySettingsAndAuditLogRenderEnabledErrorRowsAndEmptyFilters() {
        XCTAssertTrue(AppPinStore.save("123456"))
        UserDefaults.standard.set(true, forKey: enabledKey)
        let gate = SecurityGate(authenticator: SettingsAuthenticator())
        gate.errorText = "Authentication failed"
        let events = [
            AuditEvent(id: "ok", createdAt: 1, action: "delivery",
                       detail: "Delivered", outcome: "ok"),
            AuditEvent(id: "bad", createdAt: 2, action: "push",
                       detail: "Failed", outcome: "failed"),
        ]
        let audit = AuditStore(loadPersisted: false, initialEvents: events)
        assertRendered(List { SettingsSecuritySection(security: gate, audit: audit) })
        let errors = AuditLogView(audit: audit, filter: .errors)
        XCTAssertEqual(errors.filtered.map(\.id), ["bad"])
        XCTAssertFalse(AuditLogView.formatDate(1).isEmpty)
        assertRendered(NavigationView { errors })
        let empty = AuditStore(loadPersisted: false)
        let emptyLog = AuditLogView(audit: empty)
        XCTAssertTrue(emptyLog.filtered.isEmpty)
        assertRendered(NavigationView { emptyLog })
    }

    func testContentNavigationBindingsDestinationsAndSessionOpeningBranches() async {
        let model = AppModel()
        let session = SessionInfo(
            sessionId: "navigation", agent: "codex", title: "Navigation",
            state: "idle", startedAt: 1, lastActivityAt: 2,
            tokensSession: 0, tokensLastTurn: 0
        )
        model.sessions = [session]
        let gate = SecurityGate(authenticator: SettingsAuthenticator())
        let pairing = settingsPairing(room: "room")
        let opened = ContentView(
            modelOverride: model, security: gate,
            openedSession: OpenSession(id: session.sessionId), pendingPairing: pairing,
            pairingLinkError: "Invalid pairing"
        )
        XCTAssertTrue(opened.chatNavigationActive.wrappedValue)
        XCTAssertTrue(opened.pairingPrompt.wrappedValue)
        XCTAssertTrue(opened.pairingErrorPrompt.wrappedValue)
        opened.chatNavigationActive.wrappedValue = false
        opened.pairingPrompt.wrappedValue = false
        opened.pairingErrorPrompt.wrappedValue = false
        assertRendered(opened.openedSessionDestination.environmentObject(model))
        XCTAssertEqual(ContentView.relayHost("wss://relay.test/ws?secret=value"), "relay.test")
        XCTAssertEqual(ContentView.relayHost("not a url"), "not a url")

        let missing = ContentView(
            modelOverride: model, security: gate,
            openedSession: OpenSession(id: "missing")
        )
        assertRendered(missing.openedSessionDestination.environmentObject(model))

        model.sessionToOpen = "unknown"
        ContentView(modelOverride: model, security: gate).openRequestedSession(from: [session])
        XCTAssertEqual(model.sessionToOpen, "unknown")
        model.sessionToOpen = session.sessionId
        try? await Task.sleep(nanoseconds: 800_000_000)
        ContentView(
            modelOverride: model, security: gate,
            openedSession: OpenSession(id: session.sessionId)
        ).openRequestedSession(from: [session])
        XCTAssertNil(model.sessionToOpen)

        let other = SessionInfo(
            sessionId: "other", agent: "claude", title: "Other",
            state: "idle", startedAt: 1, lastActivityAt: 2,
            tokensSession: 0, tokensLastTurn: 0
        )
        model.sessions.append(other)
        model.sessionToOpen = session.sessionId
        ContentView(
            modelOverride: model, security: gate,
            openedSession: OpenSession(id: other.sessionId)
        ).openRequestedSession(from: model.sessions)
        XCTAssertNil(model.sessionToOpen)

        model.sessionToOpen = session.sessionId
        let destination = ContentView(modelOverride: model, security: gate)
        destination.openRequestedSession(from: model.sessions)
        XCTAssertNil(model.sessionToOpen)

        let linksFetched = expectation(description: "pairing links fetched")
        linksFetched.expectedFulfillmentCount = 2
        let fetchContent = ContentView(
            modelOverride: model, security: gate,
            securePairingFetcher: { link in
                defer { linksFetched.fulfill() }
                return link.mailboxId.first == "a"
                    ? .success(pairing) : .failure(.unreachable)
            }
        )
        fetchContent.fetchPairing(secureLink(character: "a"))
        fetchContent.fetchPairing(secureLink(character: "b"))
        await fulfillment(of: [linksFetched], timeout: 2)
    }

    func testContentLifecycleCoversInactiveBackgroundActiveAndLockPaths() {
        let model = AppModel()
        let gate = SecurityGate(authenticator: SettingsAuthenticator())
        let content = ContentView(
            modelOverride: model, security: gate,
            openedSession: OpenSession(id: "open")
        )
        content.handleAppear()
        content.handleScenePhase(.inactive)
        content.handleScenePhase(.background)
        content.handleScenePhase(.active)
        content.handleLockChange(false)
        // The lock coming down puts the chat and sheets away; lifting it brings them back.
        content.handleLockChange(true)
        content.handleLockChange(false)
        content.handleLockChange(true)

        model.connected = true
        model.sessions = []
        content.handleScenePhase(.active)
    }

    func testDebugLifecycleSeedsUsageAndExercisesCaptureLaunchRoutes() async {
        let keys = [
            "GRANTTAP_DEMO", "GRANTTAP_CAPTURE_TAB", "GRANTTAP_OPEN_SESSION",
            "GRANTTAP_SETTINGS", "GRANTTAP_CHAT_HISTORY", "GRANTTAP_USAGE_SCREENSHOT",
        ]
        defer {
            keys.forEach { unsetenv($0) }
            CapabilityUsageStore.shared.clear()
        }
        setenv("GRANTTAP_DEMO", "1", 1)
        setenv("GRANTTAP_CAPTURE_TAB", "usage", 1)
        setenv("GRANTTAP_OPEN_SESSION", "1", 1)
        setenv("GRANTTAP_SETTINGS", "1", 1)
        setenv("GRANTTAP_CHAT_HISTORY", "1", 1)
        setenv("GRANTTAP_USAGE_SCREENSHOT", "1", 1)

        let model = AppModel()
        let gate = SecurityGate(authenticator: SettingsAuthenticator())
        ContentView(modelOverride: model, security: gate).handleAppear()
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertTrue(model.demoMode)
        XCTAssertFalse(CapabilityUsageStore.shared.events.isEmpty)

        keys.forEach { unsetenv($0) }
        setenv("GRANTTAP_CAPTURE_TAB", "tasks", 1)
        ContentView(modelOverride: model, security: gate).handleAppear()
        model.stopDemo()
    }

    private func settingsPairing(room: String) -> Pairing {
        Pairing(
            relayUrl: "wss://relay.test/ws", room: room, role: "phone",
            deviceName: "Settings Mac", senderId: "settings",
            myPublicKey: "public", mySecretKey: "secret", peerPublicKey: "peer"
        )
    }

    private func secureLink(character: Character) -> Pairing.SecureLink {
        Pairing.SecureLink(
            relayBase: "wss://relay.test", mailboxId: String(repeating: character, count: 32),
            transferKey: Data(repeating: 4, count: 32).base64EncodedString()
        )
    }

    private func assertRendered<V: View>(
        _ view: V, file: StaticString = #filePath, line: UInt = #line
    ) {
        let frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: frame)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = frame
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let data = UIGraphicsImageRenderer(size: frame.size).image { _ in
            controller.view.drawHierarchy(in: frame, afterScreenUpdates: true)
        }.pngData()
        XCTAssertGreaterThan(data?.count ?? 0, 2_000, file: file, line: line)
        window.isHidden = true
    }
}

@MainActor
private final class SettingsAuthenticator: DeviceOwnerAuthenticating {
    let biometryName = "Test ID"
    func authenticate(
        reason: String,
        completion: @escaping @MainActor (DeviceOwnerAuthResult) -> Void
    ) { completion(.success) }
}
