import XCTest
@testable import GrantTap

final class ShellCommandStructureTests: XCTestCase {
    func testShellStructureNeverNamesACall() {
        XCTAssertEqual(ShellCommandName.from("if [ -d build ]; then rm -rf build; fi"), "rm")
        XCTAssertEqual(ShellCommandName.from("export FOO=1; npm test"), "npm")
        XCTAssertEqual(ShellCommandName.from("for f in a b; do cat $f; done"), "cat")
        XCTAssertEqual(ShellCommandName.from("while read line; do echo $line; done < file"), "echo")
        XCTAssertEqual(ShellCommandName.from("[ -f x ] && lsof -i :8080"), "lsof")
        XCTAssertEqual(ShellCommandName.from("! grep -q x file"), "grep")
        XCTAssertEqual(ShellCommandName.from("{ sleep 1; }"), "sleep")
        XCTAssertNil(ShellCommandName.from("33644"))
        XCTAssertEqual(ShellCommandName.from("kill -STOP 33644"), "kill")
        XCTAssertNil(ShellCommandName.from("if [ -d build ]"))
        XCTAssertNil(ShellCommandName.from("true"))
        XCTAssertEqual(ShellCommandName.from("print hello"), "print")
        XCTAssertTrue(ShellCommandName.isNumber("42"))
        XCTAssertFalse(ShellCommandName.isNumber("4a"))
        XCTAssertFalse(ShellCommandName.isNumber(""))
    }

    func testEqualRowsKeepOneOrderByName() {
        let base = { (name: String, kind: CapabilityUsageKind, count: Int, failures: Int) in
            OperationalToolSummary(kind: kind, name: name, count: count, failures: failures, cancelled: 0,
                                   averageDurationMs: nil, lastUsedAt: 0)
        }
        let rows = [base("wc", .cli, 1, 0), base("cp", .cli, 1, 0), base("github", .mcp, 1, 0), base("npm", .cli, 3, 0), base("gh", .cli, 1, 1)]
        let ordered = rows.sorted(by: UsageSummaries.heaviestFirst).map(\.name)
        XCTAssertEqual(ordered, ["gh", "npm", "cp", "wc", "github"], "failures, then count, then kind, then name")
        XCTAssertEqual(rows.reversed().sorted(by: UsageSummaries.heaviestFirst).map(\.name), ordered, "the same whatever the input order")
    }
}

extension ShellCommandStructureTests {
    private func entry(_ tool: String, text: String, cli: Bool = false) -> ActivityEntry {
        ActivityEntry(
            id: tool, kind: "tool", text: text, createdAt: 1, toolName: tool,
            capabilities: cli ? [ObservedCapability(kind: .cli, name: tool, toolName: tool, commandPreview: nil,
                                                    estimatedContextTokens: nil, estimatedBaselineTokens: nil, durationMs: nil)] : nil
        )
    }

    @MainActor
    func testAWrittenFileIsNotACommandThatRan() {
        let write = entry("Write", text: "Write: /Users/me/dev/nodvox/apps/ios/GrantTap/Features/ProjectMesh/ProjectRepositories.swift")
        XCTAssertFalse(write.isShellCall)
        XCTAssertNil(write.cliCommandName, "a path is the file, not a command")
        XCTAssertEqual(ToolRowLabel.text(for: write), "WRITE · ProjectRepositories.swift")
        XCTAssertEqual(ToolRowLabel.icon(for: write), "square.and.pencil")

        let bash = entry("Bash", text: "Bash: cd ~/dev && git status")
        XCTAssertTrue(bash.isShellCall)
        XCTAssertEqual(bash.cliCommandName, "git")
        XCTAssertEqual(ToolRowLabel.text(for: bash), "CLI · git")
        XCTAssertEqual(ToolRowLabel.icon(for: bash), "terminal")

        let flagged = entry("mcp.run_terminal_cmd", text: "npm test", cli: true)
        XCTAssertTrue(flagged.isShellCall)
        XCTAssertEqual(ToolRowLabel.text(for: flagged), "CLI · npm")

        let read = entry("Read", text: "Read: ~/dev/nodvox/README.md")
        XCTAssertEqual(ToolRowLabel.text(for: read), "READ · README.md")
        XCTAssertEqual(ToolRowLabel.icon(for: read), "doc.text")
        let grep = entry("Grep", text: "Grep: pattern in src")
        XCTAssertEqual(ToolRowLabel.text(for: grep), "GREP", "a pattern is not a file")
        XCTAssertEqual(ToolRowLabel.icon(for: grep), "magnifyingglass")
        XCTAssertEqual(ToolRowLabel.icon(for: entry("WebFetch", text: "https://example.test")), "globe")
        XCTAssertEqual(ToolRowLabel.icon(for: entry("Task", text: "Explore")), "person.2")
        XCTAssertEqual(ToolRowLabel.icon(for: entry("TodoWrite", text: "x")), "checklist")
        XCTAssertEqual(ToolRowLabel.icon(for: entry("Mystery", text: "x")), "wrench.and.screwdriver")
        XCTAssertEqual(ToolRowLabel.text(for: entry("", text: "x")), L("TOOL"))
        XCTAssertEqual(ToolRowLabel.text(for: entry("Shell", text: "")), "CLI · Shell", "a shell call without a command keeps the tool")
        XCTAssertNil(ToolRowLabel.subject(of: entry("Write", text: "Write: /a b/c.swift")), "a path with spaces is left alone")
        XCTAssertNil(ToolRowLabel.subject(of: entry("Write", text: "Write: ")))

        XCTAssertTrue(ShellCommandName.isShellTool("shell_command"))
        XCTAssertTrue(ShellCommandName.isShellTool("functions.run_terminal_cmd"))
        XCTAssertFalse(ShellCommandName.isShellTool("Write"))
        XCTAssertFalse(ShellCommandName.isShellTool(nil))
        RenderProbe.render(ActivityRow(entry: write, accent: .red, compact: false).environmentObject(AppModel()))
    }
}
