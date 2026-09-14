import XCTest
@testable import GrantTap

@MainActor
final class ShellCommandNameTests: XCTestCase {
    func testTheCommandIsTheFirstRealWordWithoutItsSetupOrPath() {
        XCTAssertEqual(ShellCommandName.from("npm test"), "npm")
        XCTAssertEqual(ShellCommandName.from("cd apps/ios && xcodebuild test -scheme GrantTap"), "xcodebuild")
        XCTAssertEqual(ShellCommandName.from("FOO=1 sudo ./scripts/release/check.sh --ci"), "check.sh")
        XCTAssertEqual(ShellCommandName.from("cd ~/dev; git status | head -3"), "git")
        XCTAssertEqual(ShellCommandName.from("/opt/homebrew/bin/rg -n pattern src"), "rg")
        XCTAssertEqual(ShellCommandName.from("cat /tmp/x.log | tail -6"), "cat")
        XCTAssertEqual(ShellCommandName.from("export A=1\nls"), "ls")
        XCTAssertNil(ShellCommandName.from("--flag-only"))
        XCTAssertNil(ShellCommandName.from(""))
        XCTAssertNil(ShellCommandName.from(nil))
        XCTAssertNil(ShellCommandName.from("cd"))
        XCTAssertNil(ShellCommandName.from("cd x; DEVELOPER_DIR"), "a preview cut at a variable names nothing")
        XCTAssertEqual(ShellCommandName.from("DEVELOPER_DIR=/x xcodebuild build"), "xcodebuild")
        let shouted = ActivityEntry(
            id: "s", kind: "tool", text: "Bash: cd x; DEVELOPER_DIR=/a xcodebuild build", createdAt: 1, toolName: "Bash",
            capabilities: [ObservedCapability(kind: .cli, name: "DEVELOPER_DIR", toolName: "Bash", estimatedContextTokens: nil, estimatedBaselineTokens: nil, durationMs: nil)]
        )
        XCTAssertEqual(shouted.cliCommandName, "xcodebuild", "an older Mac's shouting name is not believed")
        XCTAssertEqual(ShellCommandName.stripToolPrefix("Bash: git status", tool: "Bash"), "git status")
        XCTAssertEqual(ShellCommandName.stripToolPrefix("git status", tool: "Bash"), "git status")
        XCTAssertEqual(ShellCommandName.stripToolPrefix("Bash: x", tool: nil), "Bash: x")
    }

    func testAnEntryIsNamedByTheMacFirstThenByItsOwnText() {
        let named = ActivityEntry(
            id: "1", kind: "tool", text: "Bash: cd repo && npm run build", createdAt: 1, toolName: "Bash",
            capabilities: [ObservedCapability(kind: .cli, name: "npm", toolName: "Bash", estimatedContextTokens: 1, estimatedBaselineTokens: nil, durationMs: 10)]
        )
        XCTAssertEqual(named.cliCommandName, "npm")
        // A Mac that only knew the tool leaves the phone to read the text.
        let toolOnly = ActivityEntry(
            id: "2", kind: "tool", text: "Bash: cat /tmp/out | tail -6", createdAt: 1, toolName: "Bash",
            capabilities: [ObservedCapability(kind: .cli, name: "bash", toolName: "Bash", estimatedContextTokens: 1, estimatedBaselineTokens: nil, durationMs: nil)]
        )
        XCTAssertEqual(toolOnly.cliCommandName, "cat")
        let preview = ActivityEntry(
            id: "3", kind: "tool", text: "Bash: …", createdAt: 1, toolName: "Bash",
            capabilities: [ObservedCapability(kind: .cli, name: "Bash", toolName: "Bash", commandPreview: "git push", estimatedContextTokens: nil, estimatedBaselineTokens: nil, durationMs: nil)]
        )
        XCTAssertEqual(preview.cliCommandName, "git")
        XCTAssertNil(ActivityEntry(id: "4", kind: "tool", text: "Bash: --x", createdAt: 1, toolName: "Bash").cliCommandName)
    }

    func testOneCallShowsWhatItCostLikeAFoldedRun() throws {
        XCTAssertEqual(CliCallMetrics.parts(tokens: 1_300, cpuTimeMs: 348, peakMemoryBytes: 1_600_000_000, durationMs: 6_300).count, 4)
        XCTAssertEqual(CliCallMetrics.parts(tokens: 0, cpuTimeMs: 0, peakMemoryBytes: nil, durationMs: nil), [])
        let call = ActivityEntry(
            id: "1", kind: "tool", text: "Bash: ls", createdAt: 1, toolName: "Bash",
            capabilities: [ObservedCapability(
                kind: .cli, name: "ls", toolName: "Bash", estimatedContextTokens: 79, estimatedBaselineTokens: nil, durationMs: 120,
                resource: CapabilityResourceUsage(attribution: .attributed, cpuTimeMs: 48, peakRssBytes: 12_000_000)
            )]
        )
        let line = try XCTUnwrap(call.cliMetricsLine)
        XCTAssertTrue(line.contains("CPU"), line)
        XCTAssertTrue(line.contains("peak"), line)
        XCTAssertFalse(line.contains("tok"), "tokens already sit beside the label")
        XCTAssertNil(ActivityEntry(id: "2", kind: "message", text: "hi", createdAt: 1).cliMetricsLine)
        XCTAssertNil(ActivityEntry(id: "3", kind: "tool", text: "Bash: ls", createdAt: 1, toolName: "Bash").cliMetricsLine)
        RenderProbe.render(ActivityRow(entry: call, accent: .blue, compact: false).environmentObject(AppModel()))
    }
}

extension ShellCommandNameTests {
    func testASingleCallFoldsToOneLineAndOpens() {
        let entry = ActivityEntry(
            id: "1", kind: "tool", text: "Bash: cd apps/ios &&\n   xcodebuild test   -scheme GrantTap", createdAt: 1, toolName: "Bash",
            capabilities: [ObservedCapability(kind: .cli, name: "xcodebuild", toolName: "Bash", estimatedContextTokens: 1, estimatedBaselineTokens: nil, durationMs: 1)]
        )
        XCTAssertEqual(entry.oneLinePreview, "cd apps/ios && xcodebuild test -scheme GrantTap")
        XCTAssertEqual(ActivityEntry(id: "2", kind: "tool", text: String(repeating: "x", count: 300), createdAt: 1).oneLinePreview.count, 200)
        let model = AppModel()
        RenderProbe.render(ActivityRow(entry: entry, accent: .blue, compact: false).environmentObject(model))
        RenderProbe.render(ActivityRow(entry: entry, accent: .blue, compact: false, initiallyExpanded: true).environmentObject(model))
        RenderProbe.render(ActivityRow(entry: entry, accent: .blue, compact: true).environmentObject(model))
        RenderProbe.render(FoldChevron(open: true, accent: .blue))
    }
}
