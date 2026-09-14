import XCTest
@testable import GrantTap

final class TaskComposerRouteModelTests: XCTestCase {
    func testProviderArtworkMapsEveryComposableAgentToARealAsset() {
        XCTAssertEqual(
            AgentIdentity.composeIds.map(ProviderArtwork.assetName),
            [
                "ProviderClaude",
                "ProviderCodex",
                "ProviderCursor",
                "ProviderGrok"
            ]
        )
    }

    func testRouteColumnsStayInProviderComputerWorkspaceOrder() {
        XCTAssertEqual(
            TaskComposerRouteColumn.allCases,
            [.provider, .computer, .workspace]
        )
    }

    func testLongComputerLabelIsBoundedButAccessibilityKeepsTheFullName() {
        let full = "Serhii’s extremely long English workstation name"
        let presentation = TaskComposerRouteLabel(full, maximumCharacters: 18)

        XCTAssertEqual(presentation.compact, "Serhii’s extremely…")
        XCTAssertEqual(presentation.accessibility, full)
    }

    func testComputerAvailabilityUsesHonestThreeStateTone() {
        XCTAssertEqual(ComputerAvailabilityTone(phase: .live), .live)
        XCTAssertEqual(ComputerAvailabilityTone(phase: .macOffline), .transitional)
        XCTAssertEqual(ComputerAvailabilityTone(phase: .needRepair), .transitional)
        XCTAssertEqual(ComputerAvailabilityTone(phase: .phoneOffline), .offline)
        XCTAssertEqual(ComputerAvailabilityTone(phase: .notLinked), .offline)
    }

    func testComposerPrefersPublishedMachineNameOverPhonePairingLabel() {
        XCTAssertEqual(
            TaskComposerRoutePresentation.computerName(
                pairingLabel: "Phone", publishedMachineName: "Serhii MacBook"
            ),
            "Serhii MacBook"
        )
    }

    func testProviderMetadataShowsComputerAvailabilityAndMcpCount() {
        XCTAssertEqual(
            TaskComposerRoutePresentation.providerMetadata(phase: .live, mcpCount: 1),
            "Online · 1 MCP"
        )
        XCTAssertEqual(
            TaskComposerRoutePresentation.providerMetadata(phase: .phoneOffline, mcpCount: 0),
            "Offline · No MCP"
        )
    }

    func testNewTaskProviderUsesSavedThenRecentRouteWithoutForcingCodex() {
        let enabled: Set<String> = ["claude", "codex", "cursor", "grok"]
        let recent = SessionInfo(
            sessionId: "recent", agent: "cursor", title: "Recent", state: "idle",
            startedAt: 10, lastActivityAt: 20, tokensSession: 0, tokensLastTurn: 0
        )

        XCTAssertEqual(
            TaskComposerRoutePresentation.defaultProvider(
                saved: "grok", sessions: [recent], enabledProviders: enabled
            ),
            "grok"
        )
        XCTAssertEqual(
            TaskComposerRoutePresentation.defaultProvider(
                saved: nil, sessions: [recent], enabledProviders: enabled
            ),
            "cursor"
        )
        XCTAssertEqual(
            TaskComposerRoutePresentation.defaultProvider(
                saved: "codex", sessions: [recent], enabledProviders: ["claude"]
            ),
            "claude"
        )
    }
}
