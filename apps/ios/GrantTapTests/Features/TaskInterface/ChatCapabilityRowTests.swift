import XCTest
@testable import GrantTap

/// MCP servers, skills and the shell are one question with one answer: what can
/// this chat reach, what has it cost, and can I switch it off?
final class ChatCapabilityRowTests: XCTestCase {
    private func row(
        _ kind: ChatCapabilityRow.Kind,
        _ name: String,
        allowed: Bool? = true,
        calls: Int = 0,
        tokens: Int = 0,
        needsAuth: Bool = false
    ) -> ChatCapabilityRow {
        ChatCapabilityRow(kind: kind, name: name, allowed: allowed,
                          calls: calls, tokens: tokens, needsAuth: needsAuth)
    }

    func testTheHeaviestCapabilityLeadsTheList() {
        let ranked = ChatCapabilitySort.rank([
            row(.mcp, "quiet"),
            row(.mcp, "expensive", calls: 3, tokens: 9_000),
            row(.skill, "busy", calls: 7, tokens: 100),
        ])
        XCTAssertEqual(ranked.map(\.name), ["expensive", "busy", "quiet"])
    }

    func testUnusedCapabilitiesStayAlphabeticalRatherThanRandom() {
        let ranked = ChatCapabilitySort.rank([
            row(.mcp, "zulu"), row(.skill, "alpha"), row(.cli, "mike"),
        ])
        XCTAssertEqual(ranked.map(\.name), ["alpha", "mike", "zulu"])
    }

    func testShareIsNilWhenNothingHasBeenMeasured() {
        let rows = [row(.mcp, "a"), row(.mcp, "b")]
        XCTAssertNil(
            ChatCapabilitySort.share(of: rows[0], in: rows),
            "a zero denominator must not become a confident 0%"
        )
    }

    func testShareIsRelativeToTheChatsMeasuredTokens() {
        let rows = [row(.mcp, "a", tokens: 750), row(.mcp, "b", tokens: 250)]
        XCTAssertEqual(ChatCapabilitySort.share(of: rows[0], in: rows) ?? 0, 0.75, accuracy: 0.0001)
    }

    func testACapabilityThatNeverRanShowsNoUsageAtAll() {
        XCTAssertNil(row(.mcp, "idle").usage, "never called is not 0 tokens, it is unknown")
        XCTAssertEqual(row(.mcp, "used", calls: 2).usage, "2×")
    }

    func testAnUnenforceableSwitchIsMarkedReadOnly() {
        XCTAssertFalse(row(.cli, "shell", allowed: nil).isControllable)
        XCTAssertTrue(row(.cli, "shell", allowed: false).isControllable)
    }

    func testAControllableSwitchNamesItsStateInsteadOfRelyingOnTrackColor() {
        XCTAssertEqual(row(.mcp, "on", allowed: true).controlLabel, L("On"))
        XCTAssertEqual(row(.mcp, "off", allowed: false).controlLabel, L("Off"))
        XCTAssertNil(row(.skill, "observed", allowed: nil).controlLabel)
    }

    func testEveryKindCarriesItsOwnHeadingAndIcon() {
        for kind in ChatCapabilityRow.Kind.allCases {
            XCTAssertFalse(kind.title.isEmpty)
            XCTAssertFalse(kind.systemImage.isEmpty)
        }
    }

    func testIdentityKeepsKindsApart() {
        XCTAssertNotEqual(row(.mcp, "same").id, row(.skill, "same").id)
    }
}
