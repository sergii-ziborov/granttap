import XCTest
@testable import GrantTap

/// Choosing a model or a permission mode changes what runs on the computer, so
/// the rules for what may be chosen — and what silently must not be sent — are
/// worth pinning down.
final class TurnOverridesTests: XCTestCase {
    func testProviderModelsAreNotFrozenToAnOldGeneration() {
        for id in ["gpt-6-sol", "gpt-6-astra", "gpt-6-luna", "future-coding-model"] {
            let choice = TurnModel(rawValue: id)
            XCTAssertNotNil(choice)
            XCTAssertEqual(TurnOverrides(model: choice).wire(for: "codex").model, id)
            XCTAssertNil(TurnOverrides(model: choice).wire(for: "claude").model)
        }
        for id in ["", "--model", "a\nb", "a b", String(repeating: "a", count: 161)] {
            XCTAssertNil(TurnModel(rawValue: id))
        }
    }

    func testATurnThatChoosesNothingCarriesNothing() {
        let wire = TurnOverrides.unchanged.wire(for: "claude")
        XCTAssertNil(wire.model)
        XCTAssertNil(wire.permissionMode)
    }

    func testTheChatsOwnChoiceBeatsTheGlobalDefault() {
        let resolved = TurnOverrides.resolve(
            chat: TurnOverrides(model: .haiku, permissionMode: nil),
            fallback: TurnOverrides(model: .opus, permissionMode: .plan)
        )
        XCTAssertEqual(resolved.model, .haiku)
        XCTAssertEqual(resolved.permissionMode, .plan, "an unset chat field falls back")
    }

    func testNothingChosenAnywhereStaysUnchanged() {
        XCTAssertEqual(
            TurnOverrides.resolve(chat: .unchanged, fallback: .unchanged),
            .unchanged
        )
    }

    func testProvidersReceiveOnlyModelsTheyActuallySupport() {
        let picked = TurnOverrides(model: .opus, permissionMode: .bypassPermissions)
        for agent in ["cursor", "grok"] {
            let wire = picked.wire(for: agent)
            XCTAssertNil(wire.model, "\(agent) takes no model alias")
            XCTAssertNil(wire.permissionMode, "\(agent) takes no permission mode")
        }
        for (provider, id) in [("cursor", "composer-future"), ("grok", "grok-future")] {
            XCTAssertEqual(TurnOverrides(model: TurnModel(rawValue: id)).wire(for: provider).model, id)
        }
        XCTAssertNil(picked.wire(for: "codex").model, "a Claude alias is not a Codex model")
        XCTAssertEqual(
            TurnOverrides(model: .gpt56Terra, permissionMode: nil).wire(for: "codex").model,
            "gpt-5.6-terra"
        )
    }

    func testClaudeReceivesExactlyTheAliasTheCliExpects() {
        let wire = TurnOverrides(model: .opus, permissionMode: .bypassPermissions).wire(for: "claude")
        XCTAssertEqual(wire.model, "opus")
        XCTAssertEqual(wire.permissionMode, "bypassPermissions")
    }

    func testTheStrongestModeExplainsWhatItGivesUp() {
        XCTAssertTrue(
            TurnPermissionMode.bypassPermissions.detail.contains("without asking"),
            "removing a safety step must be readable before it is chosen"
        )
    }

    func testEveryModeMapsToAValueTheCliDefines() {
        // The CLI defines acceptEdits, auto, bypassPermissions, manual, dontAsk
        // and plan. It does not define "default", so that case must travel as
        // nothing at all rather than as a word the agent would reject.
        XCTAssertEqual(
            Set(TurnPermissionMode.allCases.compactMap(\.wireValue)),
            ["acceptEdits", "bypassPermissions", "plan"]
        )
        XCTAssertNil(TurnPermissionMode.default.wireValue)
        XCTAssertNil(
            TurnOverrides(model: nil, permissionMode: .default).wire(for: "claude").permissionMode
        )
    }

    func testEffortReachesProvidersThatAcceptIt() {
        for provider in ["codex", "claude", "grok"] {
            XCTAssertEqual(TurnOverrides(effort: .high).wire(for: provider).effort, "high")
        }
        XCTAssertNotNil(TurnEffort(rawValue: "ultra"))
        XCTAssertNil(TurnOverrides(effort: .high).wire(for: "cursor").effort)
        XCTAssertNil(TurnOverrides.unchanged.wire(for: "codex").effort)
    }

    func testStoredChatEffortSurvivesRelaunchAndWinsOverProviderDefault() throws {
        let suite = "GrantTap.effort.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TurnOverrideStore(defaults: defaults)
        store.setAgentDefaults(TurnOverrides(effort: .medium), for: "codex")
        store.setChatOverrides(TurnOverrides(effort: .high), for: "chat-a")
        let restored = TurnOverrideStore(defaults: defaults)
        XCTAssertEqual(restored.resolved(sessionId: "chat-a", agent: "codex").wire(for: "codex").effort, "high")
        XCTAssertEqual(restored.resolved(sessionId: "chat-b", agent: "codex").wire(for: "codex").effort, "medium")
    }

    func testCatalogFiltersEffortToTheSelectedNativeModelsLevels() {
        let catalog = TurnModelCatalog(options: [TurnModelOption(model: .gpt56Terra,
            label: "Test", detail: "Native", supportedEfforts: [.low, .high])])
        XCTAssertEqual(catalog.efforts(for: TurnModel.gpt56Terra.id, agent: "codex"), [.low, .high])
        XCTAssertEqual(catalog.efforts(for: nil, agent: "cursor"), [])
        XCTAssertNil(TurnOverrides(model: .gpt56Terra, effort: .ultra).wire(for: "codex", catalog: catalog).effort)
        XCTAssertEqual(TurnOverrides(model: .gpt56Terra, effort: .high).wire(for: "codex", catalog: catalog).effort, "high")
    }

    func testAChatsEffortFallsBackToTheGlobalDefault() {
        let resolved = TurnOverrides.resolve(
            chat: TurnOverrides(model: nil, permissionMode: nil, effort: nil),
            fallback: TurnOverrides(model: nil, permissionMode: nil, effort: .max)
        )
        XCTAssertEqual(resolved.effort, .max)
        XCTAssertTrue(TurnEffort.allCases.allSatisfy { !$0.label.isEmpty })
    }

    func testEveryModelAndModeHasStableReadableMetadata() {
        XCTAssertEqual(
            TurnModel.supported(by: "CLAUDE").map(\.id),
            ["opus", "sonnet", "haiku", "fable"]
        )
        XCTAssertEqual(
            TurnModel.supported(by: "codex").map(\.id),
            [], "Codex choices come from this computer's provider catalog"
        )
        XCTAssertTrue(TurnModel.allCases.allSatisfy { !$0.label.isEmpty })

        XCTAssertEqual(TurnPermissionMode.allCases.map(\.id), [
            "default", "acceptEdits", "bypassPermissions", "plan",
        ])
        XCTAssertTrue(TurnPermissionMode.allCases.allSatisfy { !$0.label.isEmpty })
        XCTAssertTrue(TurnPermissionMode.allCases.allSatisfy { !$0.detail.isEmpty })
        XCTAssertEqual(
            TurnPermissionMode.supported(by: "Claude"), TurnPermissionMode.allCases
        )
        XCTAssertTrue(TurnPermissionMode.supported(by: "cursor").isEmpty)
    }
}
