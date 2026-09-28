import XCTest
@testable import GrantTap

/// Choosing a model or a permission mode changes what runs on the computer, so
/// the rules for what may be chosen — and what silently must not be sent — are
/// worth pinning down.
final class TurnOverridesTests: XCTestCase {
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

    func testEffortReachesOnlyTheProviderThatAcceptsIt() {
        XCTAssertEqual(
            TurnEffort.supported(by: "claude").map(\.rawValue),
            ["low", "medium", "high", "xhigh", "max"]
        )
        // Codex is not driven with an effort flag here, so choosing one must not
        // travel as a value its CLI would reject.
        for agent in ["codex", "cursor", "grok"] {
            XCTAssertTrue(TurnEffort.supported(by: agent).isEmpty, agent)
            XCTAssertNil(
                TurnOverrides(model: nil, permissionMode: nil, effort: .high)
                    .wire(for: agent).effort, agent
            )
        }
        XCTAssertEqual(
            TurnOverrides(model: nil, permissionMode: nil, effort: .xhigh)
                .wire(for: "claude").effort, "xhigh"
        )
        XCTAssertNil(TurnOverrides.unchanged.wire(for: "claude").effort)
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
            ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5"]
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
