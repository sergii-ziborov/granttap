import XCTest
@testable import GrantTap

/// Models differ per provider and every chat may want its own answer settings,
/// so a single shared pair was wrong in both directions.
final class TurnOverrideStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: TurnOverrideStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "granttap.turn-overrides.\(UUID().uuidString)")
        store = TurnOverrideStore(defaults: defaults)
    }

    func testEachProviderKeepsItsOwnDefault() {
        store.setAgentDefaults(TurnOverrides(model: .opus, permissionMode: nil), for: "claude")
        store.setAgentDefaults(TurnOverrides(model: .haiku, permissionMode: nil), for: "codex")

        XCTAssertEqual(store.agentDefaults(for: "claude").model, .opus)
        XCTAssertEqual(store.agentDefaults(for: "codex").model, .haiku)
        XCTAssertNil(
            store.agentDefaults(for: "grok").model,
            "an untouched provider must not inherit someone else's model"
        )
    }

    func testEachChatKeepsItsOwnChoice() {
        store.setChatOverrides(TurnOverrides(model: .sonnet, permissionMode: nil), for: "chat-a")
        XCTAssertEqual(store.chatOverrides("chat-a").model, .sonnet)
        XCTAssertNil(store.chatOverrides("chat-b").model, "chats do not share overrides")
    }

    func testAChatsChoiceBeatsItsProvidersDefault() {
        store.setAgentDefaults(TurnOverrides(model: .opus, permissionMode: .plan), for: "claude")
        store.setChatOverrides(TurnOverrides(model: .haiku, permissionMode: nil), for: "chat-a")

        let resolved = store.resolved(sessionId: "chat-a", agent: "claude")
        XCTAssertEqual(resolved.model, .haiku, "the chat wins")
        XCTAssertEqual(resolved.permissionMode, .plan, "an unset chat field still falls back")
    }

    func testNothingChosenAnywhereStaysUnchanged() {
        XCTAssertEqual(store.resolved(sessionId: "fresh", agent: "claude"), .unchanged)
    }

    func testClearingAChoiceReturnsItToTheDefault() {
        store.setAgentDefaults(TurnOverrides(model: .opus, permissionMode: nil), for: "claude")
        store.setChatOverrides(TurnOverrides(model: .haiku, permissionMode: nil), for: "chat-a")
        store.setChatOverrides(.unchanged, for: "chat-a")

        XCTAssertEqual(store.resolved(sessionId: "chat-a", agent: "claude").model, .opus)
    }

    func testChoicesSurviveARelaunch() {
        store.setAgentDefaults(TurnOverrides(model: .fable, permissionMode: .acceptEdits), for: "claude")
        store.setChatOverrides(TurnOverrides(model: nil, permissionMode: .plan), for: "chat-a")

        let reopened = TurnOverrideStore(defaults: defaults)
        XCTAssertEqual(reopened.agentDefaults(for: "claude").model, .fable)
        XCTAssertEqual(reopened.chatOverrides("chat-a").permissionMode, .plan)
    }

    func testProviderNamesAreMatchedTheSameWayEverywhereElse() {
        store.setAgentDefaults(TurnOverrides(model: .opus, permissionMode: nil), for: "Claude")
        XCTAssertEqual(
            store.agentDefaults(for: "claude").model, .opus,
            "casing must not create a second, invisible default"
        )
    }
}
