import SwiftUI
import UIKit
import XCTest
@testable import GrantTap

@MainActor
final class UIActionCoverageTests: XCTestCase {
    func testHistoryFiltersDestinationsAndExplicitActions() {
        let model = AppModel()
        let session = uiSession(id: "history", agent: "codex")
        model.sessionHistory = [session]
        assertRendered(ChatHistorySheet(
            search: "history", agent: "codex",
            openedSession: HistoryOpenSession(id: session.sessionId)
        ).environmentObject(model))
        assertRendered(ChatHistorySheet(
            search: "missing", agent: "claude"
        ).environmentObject(model))

        let sheet = ChatHistorySheet().environmentObject(model)
        assertRendered(sheet)
        let action = ChatHistorySheet()
        action.open(session)
        action.open(session)
        action.toggleArchived(session, using: model)
        XCTAssertTrue(model.isArchived(session.sessionId))
        action.toggleArchived(session, using: model)
        XCTAssertFalse(model.isArchived(session.sessionId))
    }

    func testConnectionSectionActionsAndDialogStatesUsePersonalRoutes() async {
        let model = AppModel()
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            .empty, pairing: uiPairing(room: "first"), prefer: true
        )
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            model.connectionRegistry, pairing: uiPairing(room: "second"), prefer: false
        )
        var pairCount = 0
        var forgetCount = 0
        let second = try! XCTUnwrap(model.connectionRegistry.connections.last)
        let section = SettingsConnectionSection(
            onPair: { pairCount += 1 }, onForgetAll: { forgetCount += 1 },
            busyRoom: second.id, unlinkRoom: "missing"
        )
        assertRendered(section.environmentObject(model))
        section.requestUnlink(second)
        section.unlinkSelected(using: model)
        section.prefer(second, using: model)
        await section.runConnectionAction(second, phase: .needRepair, using: model)
        XCTAssertEqual(pairCount, 1)
        XCTAssertEqual(model.connectionRegistry.preferredId, second.id)
        XCTAssertEqual(forgetCount, 0)
    }

    func testSubscriptionManageUsesInjectedForegroundSceneSuccessAndFailure() async throws {
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        var managed = 0
        let store = SubscriptionStore(
            startObserving: false,
            manageSubscriptions: { _ in managed += 1 }
        )
        await store.manage(in: scene)
        XCTAssertEqual(managed, 1)

        let failed = SubscriptionStore(
            startObserving: false,
            manageSubscriptions: { _ in throw UIActionFixtureError.failed }
        )
        await failed.manage(in: scene)
        XCTAssertNotNil(failed.lastError)
        failed.clearError()
        XCTAssertNil(failed.lastError)
    }

    func testTaskControlBindingsMapPersonalModesAndProviderAccess() {
        let model = AppModel()
        let session = SessionInfo(
            sessionId: "controls", agent: "codex", title: "Controls", cwd: "/repo",
            model: "gpt", accessLevel: "read-only", state: "working",
            startedAt: 1, lastActivityAt: 2, tokensSession: 1, tokensLastTurn: 1
        )
        let rows = [
            ChatCapabilityRow(kind: .mcp, name: "github", allowed: true,
                              calls: 2, tokens: 10, needsAuth: false),
            ChatCapabilityRow(kind: .skill, name: "documents", allowed: nil,
                              calls: 1, tokens: 2, needsAuth: false),
            ChatCapabilityRow(kind: .cli, name: "shell", allowed: false,
                              calls: 0, tokens: 0, needsAuth: true),
        ]
        let sheet = ChatCapabilitySheet(
            sessionId: session.sessionId, session: session, rows: rows,
            accent: .blue, model: model, onToggle: { _ in }
        )
        assertRendered(sheet.environmentObject(model))
        XCTAssertEqual(sheet.approvalBinding.wrappedValue, .risky)
        // Model and effort moved to the section that owns both choices.
        let overrides = ChatTurnOverridesSection(
            sessionId: session.sessionId, agent: session.agent, model: model
        )
        assertRendered(overrides.environmentObject(model))
        XCTAssertEqual(TurnModel.supported(by: session.agent).map(\.id), [
            "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5",
        ])
        var picked = model.turnOverrides.chatOverrides(session.sessionId)
        picked.model = .gpt56Terra
        model.turnOverrides.setChatOverrides(picked, for: session.sessionId)
        XCTAssertEqual(
            model.turnOverrides.chatOverrides(session.sessionId).model,
            .gpt56Terra
        )
        // Codex is not driven with an effort flag, so it is offered none.
        XCTAssertTrue(TurnEffort.supported(by: session.agent).isEmpty)

        model.excludedSessions = [session.sessionId]
        XCTAssertEqual(sheet.approvalBinding.wrappedValue, .defaults)
        model.excludedSessions = []
        model.autoAcceptBySession[session.sessionId] = "ask"
        XCTAssertEqual(sheet.approvalBinding.wrappedValue, .every)
        model.autoAcceptBySession = [:]

        sheet.approvalBinding.wrappedValue = .defaults
        sheet.approvalBinding.wrappedValue = .every
        sheet.approvalBinding.wrappedValue = .risky
        XCTAssertTrue(model.log.contains { $0.contains("blocked") })

        XCTAssertEqual(sheet.accessBinding.wrappedValue, "read-only")
        sheet.accessBinding.wrappedValue = "full"
        XCTAssertTrue(model.log.last?.contains("blocked") == true)
        XCTAssertEqual(sheet.legacyLabel("safe"), AutoAcceptLevel.safe.title)
        XCTAssertEqual(sheet.legacyLabel("except_destructive"), AutoAcceptLevel.exceptDestructive.title)
        XCTAssertEqual(sheet.legacyLabel("full"), AutoAcceptLevel.full.title)

        for row in rows {
            assertRendered(ChatCapabilityRowView(
                row: row, accent: .blue, onToggle: {}
            ))
        }
    }

    func testUsageHistoryLinksOnlyExactAuthenticatedComputerAndCatalogRows() {
        let model = AppModel()
        model.sessionSourceRooms = [:]
        let first = uiPairing(room: "first")
        let second = uiPairing(room: "second")
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: first)
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            model.connectionRegistry, pairing: second, prefer: false
        )
        let target = CapabilityChatTarget(
            kind: "chat", roomId: first.room, sessionId: "native"
        )
        var event = CapabilityUsageEvent(
            id: "event", sourceId: "source", sourceRoom: first.room,
            agent: "codex", model: "gpt", kind: .mcp, name: "github",
            sessionId: "native", createdAt: 1, deepLinkTarget: target
        )
        // The Tools rows are the only way in, so the destination must stay reachable.
        assertRendered(CapabilityUsageView())
        let view = CapabilityUsageHistoryView(
            kind: .mcp, name: "github", agent: "codex", modelName: "gpt",
            appModel: model
        )
        XCTAssertEqual(view.attribution(.measured), L("Attribution: measured"))
        XCTAssertEqual(view.attribution(.attributed), L("Attribution: attributed"))
        XCTAssertEqual(view.attribution(.estimated), L("Attribution: estimated"))
        XCTAssertEqual(view.attribution(.unknown), L("Attribution: unknown"))
        let skillView = CapabilityUsageHistoryView(
            kind: .skill, name: "documents", agent: nil, modelName: nil,
            appModel: model
        )
        XCTAssertEqual(skillView.attribution(.attributed),
                       L("Attribution: observed during skill execution"))
        XCTAssertTrue(view.matches(event), "nil provider/model filters are wildcards")
        let failedOnly = CapabilityUsageHistoryView(
            kind: .mcp, name: "github", agent: nil, modelName: nil,
            outcome: .error, appModel: model
        )
        event.outcome = .error
        XCTAssertTrue(failedOnly.matches(event))
        event.outcome = .success
        XCTAssertFalse(failedOnly.matches(event))
        XCTAssertEqual(event.deepLinkTarget, target)
        XCTAssertEqual(event.sourceRoom, target.roomId)
        XCTAssertEqual(event.sessionId, target.sessionId)
        XCTAssertTrue(model.connectionRegistry.connections.contains { $0.id == target.roomId })
        XCTAssertEqual(view.linkedTarget(for: event), target)
        model.rememberSessionSourceRoom(first.room, sessionId: "native")
        XCTAssertEqual(view.linkedTarget(for: event), target)
        model.rememberSessionSourceRoom(second.room, sessionId: "native")
        XCTAssertNil(view.linkedTarget(for: event))
        event.sourceRoom = second.room
        XCTAssertNil(view.linkedTarget(for: event))

        model.sessionIdAliases["native"] = "resolved"
        let resolved = uiSession(id: "resolved", agent: "codex")
        model.sessions = [resolved]
        XCTAssertEqual(view.linkedSession(for: target)?.sessionId, "resolved")
        model.sessions = []
        model.sessionHistory = [resolved]
        XCTAssertEqual(view.linkedSession(for: target)?.sessionId, "resolved")
        model.sessionHistory = []
        model.archivedSessions = ["resolved": resolved]
        XCTAssertEqual(view.linkedSession(for: target)?.sessionId, "resolved")
        model.archivedSessions = [:]
        XCTAssertNil(view.linkedSession(for: target))
    }

    private func uiSession(id: String, agent: String) -> SessionInfo {
        SessionInfo(
            sessionId: id, agent: agent, title: "History task", cwd: "/repo",
            summary: "Finished", state: "idle", startedAt: 1, lastActivityAt: 2,
            tokensSession: 1, tokensLastTurn: 1
        )
    }

    private func uiPairing(room: String) -> Pairing {
        Pairing(
            relayUrl: "ws://127.0.0.1:1", room: room, role: "phone",
            deviceName: room, senderId: "sender", myPublicKey: "public",
            mySecretKey: "secret", peerPublicKey: "peer"
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

private enum UIActionFixtureError: Error { case failed }
