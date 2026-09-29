import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class TurnModelCatalogTests: XCTestCase {
    private func row(_ id: String, provider: String = "codex", endpoint: String = "mac-a",
                     source: String = "advertised", priority: Int? = nil) -> ProjectAdvertisedModel {
        ProjectAdvertisedModel(modelId: id, provider: provider, endpointId: endpoint,
            source: source, label: id.uppercased(), description: "Provider description",
            priority: priority, observedAt: 1_000)
    }

    func testAvailableModelsUseExactProviderAndComputerInProviderOrder() {
        let catalog = ProjectEndpointModelCatalog(endpointId: "mac-a", observedAt: 2_000, models: [
            row("gpt-6-sol", priority: 2), row("gpt-6-astra", priority: 1),
            row("future-coding-model", priority: 3), row("claude-opus-5", provider: "claude"),
            row("foreign-model", endpoint: "mac-b"), row("old-model", source: "observed"),
            row("gpt-6-sol"), row("--invalid"),
        ])
        let resolved = TurnModelCatalog.resolve(agent: "Codex", endpointId: "mac-a", catalogs: [catalog], now: 2_000)
        XCTAssertEqual(resolved.options.map(\.id), ["gpt-6-astra", "gpt-6-sol", "future-coding-model"])
        XCTAssertEqual(resolved.options[0].detail, "Provider description")
        XCTAssertEqual(resolved.options[0].label, "GPT-6-ASTRA")
        XCTAssertEqual(resolved.checkedAt, 1_000)
        XCTAssertFalse(resolved.stale)
        XCTAssertTrue(TurnModelCatalog.resolve(agent: "codex", endpointId: "mac-b", catalogs: [catalog], now: 2_000).options.isEmpty)
        XCTAssertTrue(TurnModelCatalog.resolve(agent: "codex", endpointId: nil, catalogs: [catalog], now: 2_000).options.isEmpty)
    }

    func testExpiredAndObservedModelsCannotPretendToBeCurrent() {
        let old = ProjectEndpointModelCatalog(endpointId: "mac-a", observedAt: 1,
            models: [row("removed-model")])
        let latest = ProjectEndpointModelCatalog(endpointId: "mac-a", observedAt: 2,
            stale: true, models: [row("old-model")])
        let result = TurnModelCatalog.resolve(agent: "codex", endpointId: "mac-a", catalogs: [old, latest], now: 2_000)
        XCTAssertTrue(result.options.isEmpty)
        XCTAssertTrue(result.stale)
        XCTAssertTrue(TurnModelCatalog.resolve(agent: "codex", endpointId: "mac-a",
            catalogs: [old], now: 25 * 60 * 60_000).options.isEmpty)
        let aliases = TurnModelCatalog.resolve(agent: "claude", endpointId: nil, catalogs: [])
        XCTAssertEqual(aliases.options.map(\.id), ["opus", "sonnet", "haiku", "fable"])
        XCTAssertTrue(aliases.options.allSatisfy { !$0.detail.isEmpty })
        XCTAssertTrue(TurnModelCatalog.resolve(agent: "cursor", endpointId: nil, catalogs: []).options.isEmpty)
    }

    func testSwitchWarningOnlyForAChangedExistingConversationIncludingReturningToDefault() {
        let astra = TurnModel(rawValue: "gpt-6-astra")!
        XCTAssertTrue(TurnModelChange.needsConfirmation(choice: astra, selection: nil,
            current: "gpt-6-sol", fallback: nil, hasConversation: true))
        XCTAssertFalse(TurnModelChange.needsConfirmation(choice: astra, selection: nil,
            current: "gpt-6-astra", fallback: nil, hasConversation: true))
        XCTAssertFalse(TurnModelChange.needsConfirmation(choice: astra, selection: nil,
            current: "gpt-6-sol", fallback: nil, hasConversation: false))
        XCTAssertTrue(TurnModelChange.needsConfirmation(choice: nil, selection: astra,
            current: "gpt-6-sol", fallback: "gpt-6-luna", hasConversation: true))
        XCTAssertTrue(TurnModelChange.needsConfirmation(choice: astra, selection: nil,
            current: nil, fallback: nil, hasConversation: true))
        XCTAssertEqual(TurnModelChange(choice: nil).id, "current")
        XCTAssertEqual(TurnModelChange(choice: astra).id, astra.id)
    }

    func testNewModelChoiceSurvivesRelaunchAndTheQueuedMessageKeepsIt() {
        let defaults = UserDefaults(suiteName: "model-choice-\(UUID())")!
        let store = TurnOverrideStore(defaults: defaults)
        store.setChatOverrides(TurnOverrides(model: TurnModel(rawValue: "future-coding-model")), for: "chat")
        let reopened = TurnOverrideStore(defaults: defaults)
        XCTAssertEqual(reopened.chatOverrides("chat").model?.rawValue, "future-coding-model")
        let app = AppModel()
        app.demoMode = true
        let session = SessionInfo(sessionId: "chat", agent: "codex", model: "gpt-6-sol",
            state: "working", startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        XCTAssertTrue(app.queueChatMessage("Continue", to: session, overrides: reopened.chatOverrides("chat")))
        XCTAssertEqual(app.deliveries.last?.model, "future-coding-model")
    }

    func testCatalogDetailsDecodeAndOldWireModelsStillDecode() throws {
        let data = try JSONEncoder().encode(row("gpt-6-sol", priority: 2))
        let decoded = try JSONDecoder().decode(ProjectAdvertisedModel.self, from: data)
        XCTAssertEqual(decoded.description, "Provider description")
        XCTAssertEqual(decoded.priority, 2)
        let old = Data(#"{"modelId":"gpt-5.5","provider":"codex","endpointId":"mac","source":"observed","observedAt":1}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(ProjectAdvertisedModel.self, from: old).description)
        XCTAssertFalse(TurnModel.opus.accepted(by: "cursor"))
        RenderProbe.render(ComposerModelPill(agent: "codex", model: .constant(nil), current: "gpt-6-sol"), height: 60)
    }
}
