import SwiftUI
import XCTest
@testable import GrantTapWatch

@MainActor
final class WatchJourneyCoverageTests: XCTestCase {
    override func setUp() {
        super.setUp()
        setenv("GRANTTAP_DEMO", "1", 1)
        WatchBridge.shared.start()
    }

    override func tearDown() {
        unsetenv("GRANTTAP_DEMO")
        unsetenv("GRANTTAP_WATCH_CAPTURE")
        unsetenv("GRANTTAP_TEST_LANGUAGE")
        UserDefaults.standard.removeObject(forKey: AppLocale.storageKey)
        WatchBridge.shared.state = WatchState()
        WatchBridge.shared.hasLiveData = false
        super.tearDown()
    }

    func testDemoRootAndTaskJourneysBuildTheirViews() throws {
        let state = WatchBridge.shared.state
        let session = try XCTUnwrap(state.sessions.first)

        XCTAssertEqual(state.approvals.count, 1)
        XCTAssertEqual(state.sessions.count, 3)
        assertRendered(WatchRootView())
        assertRendered(UnifiedTaskPage())
        assertRendered(SessionsOverview(sessions: state.sessions))
        assertRendered(SessionActivityView(session: session))
        assertRendered(TaskPreviewRow(session: session))
    }

    func testDecisionQuestionAndReplyJourneysBuildTheirViews() throws {
        let approval = try XCTUnwrap(WatchBridge.shared.state.approvals.first)
        let question = WatchQuestion(id: "question", text: "Run tests?", sessionId: approval.sessionId)
        let pending = WatchApproval(
            id: "pending", agent: "claude", title: "Publish?", command: nil,
            risk: "safe", cwd: nil, sessionId: approval.sessionId,
            waitingForMachine: true
        )

        XCTAssertTrue(WatchAction.canSendPermissionFollowUp(sessionId: approval.sessionId))
        XCTAssertNil(WatchAction.permissionFollowUp("continue", sessionId: " ", agent: "codex"))
        assertRendered(DecisionRow(approval: approval))
        assertRendered(DecisionRow(approval: pending))
        assertRendered(ChatScreen(chat: WatchChat(from: approval)))
        assertRendered(ChatScreen(chat: WatchChat(from: question)))
        assertRendered(ChatScreen(chat: WatchChat.idle(WatchBridge.shared.state)))
        assertRendered(ChatScreen(
            chat: WatchChat(from: approval), initialStep: .explain
        ))
        assertRendered(ChatScreen(
            chat: WatchChat(from: question), initialStep: .replied,
            initialReplyText: "Run the full suite", replyByVoice: false
        ))
        assertRendered(ChatScreen(
            chat: WatchChat(from: approval), permissionFollowUpSent: true
        ))
        assertRendered(ReplyInput(title: "Reply", icon: "quote.bubble", onSubmit: { _ in }))
        assertRendered(Pill(title: "Allow", action: {}))
        var submitted: [String] = []
        let normalizedInput = ReplyInput(
            title: "Reply", icon: "mic", normalizeTechnologyTerms: true,
            onSubmit: { submitted.append($0) }
        )
        normalizedInput.submit(" опен эй ай ")
        normalizedInput.submit("   ")
        XCTAssertEqual(submitted, ["OpenAI"])
        _ = WatchChat(
            id: "defaults", agent: "codex", accent: .white, risk: nil,
            ask: "Continue?", cmd: nil, isPermission: false
        )

        let permissionScreen = ChatScreen(chat: WatchChat(from: approval))
        permissionScreen.onApprove()
        permissionScreen.onDeny()
        permissionScreen.reply(voice: true, text: "Use the release branch")
        let questionScreen = ChatScreen(chat: WatchChat(from: question))
        questionScreen.reply(voice: false, text: "Yes")
        let idleScreen = ChatScreen(chat: WatchChat.idle(WatchBridge.shared.state))
        idleScreen.reply(voice: false, text: "Continue")
    }

    func testSupportingScreensAndProviderPresentationBuild() {
        XCTAssertEqual(stateWord("working"), L("working"))
        XCTAssertEqual(stateWord("waiting"), L("waiting"))
        XCTAssertEqual(sessionStateRank("idle"), 2)
        for provider in ["codex", "claude", "cursor", "grok", "unknown"] {
            _ = accentFor(provider)
            XCTAssertFalse(agentGlyph(provider).isEmpty)
        }
        assertRendered(NewVoiceTaskView(initialAgent: "unsupported"))
        assertRendered(NewVoiceTaskView(initialAgent: "claude", sentText: "Review the release"))
        assertRendered(WatchSettingsView())
        assertRendered(WatchAboutView())
        assertRendered(WatchSyncView())
        assertRendered(WatchBrandMark(size: 24))
        assertRendered(AgentConnectionNotice(
            color: .orange, title: "Offline", detail: "Open iPhone", icon: "iphone.slash"
        ))
    }

    func testActivityStatesAndEntryMerging() {
        let now = Date().timeIntervalSince1970 * 1_000
        let entries = [
            WatchActivityEntry(id: "a", kind: "message", text: "Started", createdAt: now - 2),
            WatchActivityEntry(id: "b", kind: "tool", text: "npm test", createdAt: now - 1),
        ]
        let idle = WatchSession(
            id: "idle", agent: "claude", title: "Idle task", state: "idle",
            tokensSession: 10, tokensLastTurn: 2, elapsedSec: 20
        )
        let activity = SessionActivityView(
            session: idle, initialEntries: entries, sentReply: "Continue"
        )
        assertRendered(activity)
        activity.sendReply("Ship it")
        activity.mergeEntries(entries)
        activity.mergeEntries(entries + [
            WatchActivityEntry(id: "c", kind: "final", text: "Done", createdAt: now)
        ])

        WatchBridge.shared.state = WatchState()
        assertRendered(UnifiedTaskPage())
        assertRendered(SessionsOverview(sessions: []))
        assertRendered(WatchSyncView())
    }

    func testSharedProtocolRoundTripsLegacyAndCurrentPayloads() throws {
        let legacy = Data("{\"machine\":\"Mac mini\"}".utf8)
        let decoded = try JSONDecoder().decode(WatchState.self, from: legacy)
        XCTAssertEqual(decoded.machine, "Mac mini")
        XCTAssertEqual(decoded.approvals, [])
        XCTAssertEqual(decoded.questions, [])
        XCTAssertEqual(decoded.attention, [])
        XCTAssertEqual(decoded.sessions, [])
        XCTAssertEqual(decoded.activities, [])
        XCTAssertEqual(decoded.agents, [])
        XCTAssertFalse(decoded.connected)
        XCTAssertEqual(decoded.stamp, 0)

        let attention = HumanAttentionItem(
            id: "mesh-question", kind: .meshQuestion, action: .meshReply,
            title: "Drop backward compatibility?", agent: "grok_bot",
            sessionId: "grok-bot:qa:42", projectId: "project", taskId: "task",
            createdAt: 1
        )
        let current = WatchState(attention: [attention])
        XCTAssertEqual(
            try JSONDecoder().decode(WatchState.self, from: JSONEncoder().encode(current)).attention,
            [attention]
        )

        let actions = [
            WatchAction.decision("request", "allow", sessionId: "session"),
            WatchAction.message("Continue", sessionId: "session", requestId: "question", agent: "codex"),
            WatchAction.permissionFollowUp("Continue", sessionId: " session ", agent: "Claude Code"),
            WatchAction.questionReply("Yes", sessionId: "session", requestId: "question"),
            WatchAction.meshAnswer("Yes", eventId: "mesh-question"),
            WatchAction.meshDecision("mesh-handoff", allow: true),
            WatchAction.subscription("session", active: true),
            WatchAction.newTask("Audit release", agent: "codex"),
            WatchAction.refresh(),
        ]
        for action in actions.compactMap({ $0 }) {
            let data = try JSONEncoder().encode(action)
            XCTAssertNoThrow(try JSONDecoder().decode(WatchAction.self, from: data))
        }
    }

    func testLocaleVoiceAndAgentIdentityContracts() {
        setenv("GRANTTAP_TEST_LANGUAGE", "ru", 1)
        XCTAssertEqual(AppLocale.code, "ru")
        XCTAssertEqual(AppLocale.speechIdentifier, "ru-RU")
        XCTAssertFalse(AppLocale.text("New task").isEmpty)
        setenv("GRANTTAP_TEST_LANGUAGE", "unsupported", 1)
        XCTAssertEqual(AppLocale.code, "en")
        XCTAssertEqual(AppLocale.speechIdentifier, "en-US")
        XCTAssertEqual(L("Needs You"), "Needs You")
        XCTAssertFalse(AppVersion.short.isEmpty)
        XCTAssertFalse(AppVersion.build.isEmpty)
        XCTAssertTrue(AppVersion.display.contains("("))

        let dictated = "опен эй ай , свифт ю ай и гит хаб"
        XCTAssertEqual(VoiceTextNormalizer.normalize(dictated), "OpenAI, SwiftUI и GitHub")
        XCTAssertTrue(VoiceTextNormalizer.isKnownTechnology(" кодекс! "))
        XCTAssertFalse(VoiceTextNormalizer.isKnownTechnology("GrantTap relay"))

        XCTAssertEqual(AgentIdentity.normalize("  "), "codex")
        for (source, normalized) in [
            ("Claude Code", "claude"), ("OpenAI Codex", "codex"),
            ("Cursor Agent", "cursor"),
            ("Grok Build", "grok"), ("custom agent", "custom agent"),
        ] {
            XCTAssertEqual(AgentIdentity.normalize(source), normalized)
            XCTAssertFalse(AgentIdentity.displayName(source).isEmpty)
            XCTAssertFalse(AgentIdentity.shortName(source).isEmpty)
            XCTAssertFalse(AgentIdentity.glyph(source).isEmpty)
        }
        XCTAssertEqual(AgentIdentity.displayName(""), "Codex")
        XCTAssertEqual(AgentIdentity.newTaskLabel(), "New task")
    }

    func testFeedOrderingAndCaptureRoutesExerciseEveryTieBreaker() {
        func session(_ id: String, _ agent: String, _ title: String,
                     _ state: String, _ activity: Double?) -> WatchSession {
            WatchSession(
                id: id, agent: agent, title: title, state: state,
                tokensSession: 0, tokensLastTurn: 0, elapsedSec: 0,
                lastActivityAt: activity
            )
        }
        XCTAssertTrue(sessionFeedOrder(
            session("working", "codex", "Z", "working", 1),
            session("waiting", "codex", "A", "waiting", 2)
        ))
        XCTAssertTrue(sessionFeedOrder(
            session("new", "codex", "Z", "idle", 2),
            session("old", "codex", "A", "idle", 1)
        ))
        XCTAssertTrue(sessionFeedOrder(
            session("claude", "claude", "Z", "idle", 1),
            session("codex", "codex", "A", "idle", 1)
        ))
        XCTAssertTrue(sessionFeedOrder(
            session("z", "codex", "Alpha", "idle", 1),
            session("a", "codex", "Beta", "idle", 1)
        ))
        XCTAssertTrue(sessionFeedOrder(
            session("a", "codex", "Same", "idle", 1),
            session("b", "codex", "Same", "idle", 1)
        ))
        XCTAssertEqual(sessionStateRank("working"), 0)
        XCTAssertEqual(sessionStateRank("waiting"), 1)

        setenv("GRANTTAP_WATCH_CAPTURE", "approval", 1)
        assertRendered(WatchRootView())
        setenv("GRANTTAP_WATCH_CAPTURE", "task", 1)
        assertRendered(WatchRootView())
    }

    private func assertRendered<V: View>(
        _ view: V,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let renderer = ImageRenderer(
            content: view.frame(width: 198, height: 242)
        )
        renderer.scale = 2
        XCTAssertNotNil(renderer.cgImage, file: file, line: line)
    }
}
