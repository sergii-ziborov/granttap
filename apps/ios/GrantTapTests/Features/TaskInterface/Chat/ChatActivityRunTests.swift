import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class ChatActivityRunTests: XCTestCase {
    private func tool(_ id: String, _ name: String, text: String, at: Double, summary: String? = nil,
                      mcp: String? = nil, skill: String? = nil, added: Int? = nil, tokens: Int? = nil,
                      outcome: CapabilityOutcome? = nil, cli: Bool = false) -> ActivityEntry {
        ActivityEntry(id: id, kind: "tool", text: text, createdAt: at, toolName: name, mcpServer: mcp, skill: skill,
                      capabilities: cli ? [ObservedCapability(kind: .cli, name: "git", toolName: name, commandPreview: nil,
                                                              estimatedContextTokens: nil, estimatedBaselineTokens: nil, durationMs: 40,
                                                              outcome: outcome, resource: CapabilityResourceUsage(attribution: .measured, cpuTimeMs: 12, peakRssBytes: 2_000))] : nil,
                      outcome: outcome, estimatedContextTokens: tokens, linesAdded: added, linesRemoved: added == nil ? nil : 0,
                      diffPreview: added == nil ? nil : "+a\n+b", summary: summary)
    }

    private func message(_ id: String, at: Double) -> ActivityEntry {
        ActivityEntry(id: id, kind: "message", text: "Words", createdAt: at)
    }

    private var entries: [ActivityEntry] {
        [
            tool("w", "Write", text: "Write: /repo/scripts/check-apple-key.mjs", at: 1, added: 79, tokens: 500),
            tool("b", "Bash", text: "Bash: git commit -m 'Add the key check'", at: 2, summary: "Commit the key diagnostic script", tokens: 120, cli: true),
            tool("r", "Read", text: "Read: /repo/README.md", at: 3),
            tool("g", "Grep", text: "Grep: pattern", at: 4),
            tool("m", "mcp__chrome__tabs_context_mcp", text: "chrome/tabs_context_mcp", at: 5, mcp: "chrome"),
            tool("t", "ToolSearch", text: "ToolSearch: select:Monitor", at: 6),
            tool("s", "Skill", text: "Skill: release-check", at: 7, skill: "release-check"),
            tool("f", "WebFetch", text: "WebFetch: https://example.test", at: 8, outcome: .error),
            tool("d", "Task", text: "Task: Explore the tree", at: 9, summary: "Explore the tree"),
        ]
    }

    func testEveryToolCallFoldsIntoARunAndMessagesBreakThem() {
        let items: [CombinedTaskTimelineItem] = [
            .activity(message("m1", at: 0)), .activity(entries[0]), .activity(entries[1]),
            .activity(message("m2", at: 2.5)), .activity(entries[2]),
        ]
        let rows = ChatActivityGrouping.rows(items)
        XCTAssertEqual(rows.count, 4)
        guard case .run(let first) = rows[1], case .run(let lone) = rows[3] else { return XCTFail("\(rows)") }
        XCTAssertEqual(first.calls, 2)
        XCTAssertEqual(lone.calls, 1, "one call is a run of one, the way the Claude app shows it")
        XCTAssertEqual(rows[1].id, "run:w")
        XCTAssertFalse(ChatActivityGrouping.isToolCall(message("m", at: 0)))
        XCTAssertTrue(ChatActivityGrouping.isToolCall(entries[4]), "an MCP call is a step too")
    }

    func testTheRunReadsAsASentenceAndItsStepsAsVerbs() {
        let run = ChatActivityRun(entries: entries)
        let steps = run.steps
        XCTAssertEqual(steps.map(\.kind), [.created, .ran, .read, .searched, .used, .used, .used, .fetched, .delegated])
        XCTAssertEqual(steps[0].title, L("Created"))
        XCTAssertEqual(steps[0].subject, "check-apple-key.mjs")
        XCTAssertEqual(steps[0].icon, "square.and.pencil")
        XCTAssertEqual(steps[1].subject, "Commit the key diagnostic script", "the description the agent gave, not the command")
        XCTAssertEqual(steps[2].subject, "README.md")
        XCTAssertEqual(steps[4].usedName, "Tabs Context Mcp")
        XCTAssertEqual(steps[4].title, String(format: L("Used %@"), "Tabs Context Mcp"))
        XCTAssertEqual(steps[4].icon, "shippingbox")
        XCTAssertEqual(steps[5].usedName, "ToolSearch")
        XCTAssertNil(steps[5].subject, "a plain tool with no description has nothing to add")
        XCTAssertEqual(steps[6].usedName, "\(L("skill")) release-check")
        XCTAssertTrue(steps[7].failed)
        XCTAssertEqual(steps[8].subject, "Explore the tree")
        let sentence = run.sentence
        XCTAssertTrue(sentence.hasPrefix(String(sentence.prefix(1)).uppercased()), sentence)
        for piece in [
            LPlural(1, one: "created a file", many: "created %d files"),
            LPlural(1, one: "ran a command", many: "ran %d commands"),
            LPlural(1, one: "read a file", many: "read %d files"),
            LPlural(1, one: "searched once", many: "searched %d times"),
            LPlural(1, one: "fetched a page", many: "fetched %d pages"),
            LPlural(1, one: "delegated once", many: "delegated %d times"),
            String(format: L("used %@, %@ and %d more"), "Tabs Context Mcp", "ToolSearch", 1),
        ] {
            XCTAssertTrue(sentence.lowercased().contains(piece.lowercased()), "\(piece) in \(sentence)")
        }
        let two = ChatActivityRun(entries: [entries[4], entries[5], entries[0], entries[0]]).sentence
        XCTAssertTrue(two.lowercased().contains(String(format: L("used %@ and %@"), "Tabs Context Mcp", "ToolSearch").lowercased()), two)
        XCTAssertTrue(two.contains(LPlural(2, one: "created a file", many: "created %d files")), two)
        XCTAssertEqual(ChatActivityRun(entries: []).sentence, L("Did nothing yet"))
        XCTAssertEqual(ActivityStep(entry: tool("x", "", text: "", at: 1)).usedName, L("a tool"))
        XCTAssertEqual(run.tokens, 620)
        XCTAssertEqual(run.cpuTimeMs, 12)
        XCTAssertEqual(run.peakMemoryBytes, 2_000)
        XCTAssertEqual(run.durationMs, 40)
        XCTAssertEqual(run.failures, 1)
        XCTAssertNotNil(run.metricsLine)
        XCTAssertNil(ChatActivityRun(entries: [entries[2]]).metricsLine)
    }

    func testTheRunOpensToItsStepsAndAStepToItsDetail() {
        let run = ChatActivityRun(entries: entries)
        let model = AppModel()
        RenderProbe.render(ActivityRunRow(run: run, accent: .red).environmentObject(model))
        RenderProbe.render(ActivityRunRow(run: run, accent: .red, forceOpen: true, highlightedEntryId: "b").environmentObject(model))
        RenderProbe.render(ActivityRunSheet(run: run, accent: .red, highlightedEntryId: "w").environmentObject(model))
        RenderProbe.render(NavigationView { ActivityStepDetail(step: run.steps[0], accent: .red) })
        RenderProbe.render(NavigationView { ActivityStepDetail(step: run.steps[1], accent: .red) })
        RenderProbe.render(NavigationView {
            ActivityStepDetail(step: run.steps[4], accent: .red, server: McpServerInfo(name: "chrome", configuredEnabled: true, allowed: true))
        })
        RenderProbe.render(List { ActivityStepRow(step: run.steps[7], isLast: true, highlighted: true) })

        let session = SessionInfo(sessionId: "run-chat-\(UUID().uuidString)", agent: "claude", title: "Runs", cwd: "/repo",
                                  state: "idle", startedAt: 1, lastActivityAt: 9, tokensSession: 1, tokensLastTurn: 1)
        model.sessions = [session]
        model.applyActivity(SessionActivity(sessionId: session.sessionId, agent: "claude", state: "idle",
                                            entries: [message("m1", at: 0)] + entries, generatedAt: 10))
        RenderProbe.render(NavigationView { TaskChatView(session: session, focusEntryId: "b", modelOverride: model).environmentObject(model) })
    }
}
